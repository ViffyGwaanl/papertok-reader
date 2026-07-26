import '../models/ai_api_key_entry.dart';
import '../service/ai_provider_tester.dart';

/// Cooldown/threshold policy for API-key rotation.
///
/// Read from the provider's own config (`api_key_policy_*` keys) so power
/// users can tune per provider. Defaults and clamps mirror what the reader app
/// shipped with — changing them here would change live cooldown behaviour.
class AiKeyRotationPolicy {
  const AiKeyRotationPolicy({
    this.failureThreshold = 3,
    this.authCooldown = const Duration(minutes: 60),
    this.rateLimitCooldown = const Duration(minutes: 5),
    this.serviceCooldown = const Duration(minutes: 1),
  });

  /// Consecutive failures before a key is put on cooldown.
  final int failureThreshold;

  /// Cooldown after an auth failure — a rejected key rarely heals itself, so
  /// this is the long one.
  final Duration authCooldown;
  final Duration rateLimitCooldown;

  /// Cooldown after a provider-side error; short, since 5xx usually passes.
  final Duration serviceCooldown;

  factory AiKeyRotationPolicy.fromRawConfig(Map<String, String> raw) {
    int parse(String key, int fallback) {
      final v = (raw[key] ?? '').trim();
      if (v.isEmpty) return fallback;
      return int.tryParse(v) ?? fallback;
    }

    int clampMinutes(int v) => v.clamp(1, 24 * 60);

    return AiKeyRotationPolicy(
      failureThreshold:
          parse('api_key_policy_failure_threshold', 3).clamp(1, 10),
      authCooldown: Duration(
        minutes: clampMinutes(parse('api_key_policy_auth_cooldown_min', 60)),
      ),
      rateLimitCooldown: Duration(
        minutes:
            clampMinutes(parse('api_key_policy_rate_limit_cooldown_min', 5)),
      ),
      serviceCooldown: Duration(
        minutes: clampMinutes(parse('api_key_policy_service_cooldown_min', 1)),
      ),
    );
  }

  Duration cooldownFor(AiProviderTestFailure failure) {
    switch (failure) {
      case AiProviderTestFailure.unauthorized:
        return authCooldown;
      case AiProviderTestFailure.rateLimited:
        return rateLimitCooldown;
      default:
        return serviceCooldown;
    }
  }
}

/// Classify a raw error string the way the reader app always has.
///
/// Transport layers differ (dio, http, TimeoutException…), so at rotation
/// level the lowest common denominator is the message text. Use
/// `AiProviderTester.classifyDioException` when you have a typed dio error.
AiProviderTestFailure classifyAiFailureText(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return AiProviderTestFailure.unauthorized;
  }
  if (message.contains('429') || message.contains('rate limit')) {
    return AiProviderTestFailure.rateLimited;
  }
  if (message.contains('503') || message.contains('bad gateway')) {
    return AiProviderTestFailure.serverError;
  }
  return AiProviderTestFailure.unknown;
}

/// Whether this failure class should count toward putting a key on cooldown.
///
/// Matches the historical `shouldRetry` list: auth, rate-limit and provider
/// errors are key-specific enough to bench the key; network/timeouts are not
/// the key's fault and must never bench it.
bool isAiKeyCooldownWorthy(AiProviderTestFailure failure) {
  return failure == AiProviderTestFailure.unauthorized ||
      failure == AiProviderTestFailure.rateLimited ||
      failure == AiProviderTestFailure.serverError;
}

/// One planned request attempt.
class AiKeyAttempt {
  const AiKeyAttempt({required this.apiKey, this.entry});

  /// The key to send. Falls back to the provider's single `api_key` when no
  /// managed list exists.
  final String apiKey;

  /// The managed entry behind [apiKey]; null in single-key fallback mode.
  final AiApiKeyEntry? entry;
}

/// Plan the ordered key attempts for one provider.
///
/// Semantics (distilled from the app's chat and embeddings loops, which had
/// hand-rolled the same thing twice):
/// - only enabled, non-empty keys participate;
/// - keys on cooldown are skipped while any key is available;
/// - if *every* key is cooling down, all of them are tried anyway, soonest
///   recovery first — a request in hand beats a perfectly honored cooldown;
/// - [startIndex] (the round-robin cursor) rotates the starting position;
/// - with no managed list at all, the single [fallbackApiKey] is the one
///   attempt.
List<AiKeyAttempt> planAiKeyAttempts({
  required List<AiApiKeyEntry> entries,
  required String fallbackApiKey,
  int startIndex = 0,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  bool coolingDown(AiApiKeyEntry e) {
    final until = e.disabledUntil;
    return until != null && until > now;
  }

  final enabled = entries
      .where((e) => e.enabled && e.key.trim().isNotEmpty)
      .toList(growable: false);
  final available =
      enabled.where((e) => !coolingDown(e)).toList(growable: false);

  final candidates = available.isNotEmpty
      ? available
      : (enabled.toList(growable: true)
        ..sort((a, b) => (a.disabledUntil ?? 0).compareTo(b.disabledUntil ?? 0)));

  if (candidates.isEmpty) {
    final key = fallbackApiKey.trim();
    if (key.isEmpty) return const [];
    return [AiKeyAttempt(apiKey: key)];
  }

  return List.generate(candidates.length, (i) {
    final entry = candidates[(startIndex + i) % candidates.length];
    final key = entry.key.trim();
    return AiKeyAttempt(
      apiKey: key.isNotEmpty ? key : fallbackApiKey.trim(),
      entry: entry,
    );
  }, growable: false);
}

/// Entry after a successful call: stats bumped, cooldown cleared.
AiApiKeyEntry applyAiKeySuccess(AiApiKeyEntry entry, {required int nowMs}) {
  return entry.copyWith(
    lastUsedAt: nowMs,
    lastSuccessAt: nowMs,
    successCount: (entry.successCount ?? 0) + 1,
    consecutiveFailures: 0,
    updatedAt: nowMs,
  ).withDisabledUntil(null);
}

/// Entry after a failed call: failure counted, cooldown applied once the
/// consecutive-failure threshold is crossed for a cooldown-worthy class.
AiApiKeyEntry applyAiKeyFailure(
  AiApiKeyEntry entry, {
  required int nowMs,
  required AiKeyRotationPolicy policy,
  required AiProviderTestFailure failure,
}) {
  final nextConsecutive = (entry.consecutiveFailures ?? 0) + 1;

  int? disabledUntil = entry.disabledUntil;
  if (isAiKeyCooldownWorthy(failure) &&
      nextConsecutive >= policy.failureThreshold) {
    disabledUntil = nowMs + policy.cooldownFor(failure).inMilliseconds;
  }

  return entry.copyWith(
    lastUsedAt: nowMs,
    lastFailureAt: nowMs,
    failureCount: (entry.failureCount ?? 0) + 1,
    consecutiveFailures: nextConsecutive,
    disabledUntil: disabledUntil,
    updatedAt: nowMs,
  );
}

/// Entry with its failure streak and cooldown wiped; counters untouched.
///
/// For explicit user actions ("reset stats", "I replaced the key") — unlike
/// [applyAiKeySuccess] it records no synthetic success.
AiApiKeyEntry clearAiKeyCooldown(AiApiKeyEntry entry, {required int nowMs}) {
  return entry
      .copyWith(consecutiveFailures: 0, updatedAt: nowMs)
      .withDisabledUntil(null);
}

/// Replace the matching entry (by id) in [entries].
List<AiApiKeyEntry> upsertAiKeyEntry(
  List<AiApiKeyEntry> entries,
  AiApiKeyEntry entry,
) {
  final index = entries.indexWhere((e) => e.id == entry.id);
  if (index < 0) return entries;
  final next = [...entries];
  next[index] = entry;
  return next;
}

extension _AiApiKeyEntryCooldown on AiApiKeyEntry {
  /// `copyWith` cannot null out a field; cooldown clearing needs to.
  AiApiKeyEntry withDisabledUntil(int? value) {
    return AiApiKeyEntry(
      id: id,
      name: name,
      key: key,
      enabled: enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastTestAt: lastTestAt,
      lastTestOk: lastTestOk,
      lastTestMessage: lastTestMessage,
      lastUsedAt: lastUsedAt,
      lastSuccessAt: lastSuccessAt,
      successCount: successCount,
      lastFailureAt: lastFailureAt,
      failureCount: failureCount,
      consecutiveFailures: consecutiveFailures,
      disabledUntil: value,
    );
  }
}
