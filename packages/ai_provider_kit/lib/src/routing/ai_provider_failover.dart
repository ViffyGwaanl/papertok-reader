import '../models/ai_provider_meta.dart';
import '../service/ai_provider_center.dart';
import '../service/ai_provider_tester.dart';
import 'ai_key_attempts.dart';

/// Rolling health of one provider, as seen from this device.
class AiProviderHealth {
  const AiProviderHealth({
    this.consecutiveFailures = 0,
    this.disabledUntil,
    this.lastFailure,
    this.lastOkAt,
    this.lastLatencyMs,
  });

  final int consecutiveFailures;

  /// While set and in the future, the provider is skipped as a fallback (it is
  /// never blocked as an explicit first choice).
  final int? disabledUntil;
  final AiProviderTestFailure? lastFailure;
  final int? lastOkAt;
  final int? lastLatencyMs;

  bool coolingDownAt(int nowMs) =>
      disabledUntil != null && disabledUntil! > nowMs;

  Map<String, dynamic> toJson() => {
        'consecutiveFailures': consecutiveFailures,
        if (disabledUntil != null) 'disabledUntil': disabledUntil,
        if (lastFailure != null) 'lastFailure': lastFailure!.name,
        if (lastOkAt != null) 'lastOkAt': lastOkAt,
        if (lastLatencyMs != null) 'lastLatencyMs': lastLatencyMs,
      };

  factory AiProviderHealth.fromJson(Map<String, dynamic> json) {
    AiProviderTestFailure? failure;
    final rawFailure = json['lastFailure']?.toString();
    if (rawFailure != null) {
      for (final value in AiProviderTestFailure.values) {
        if (value.name == rawFailure) {
          failure = value;
          break;
        }
      }
    }
    return AiProviderHealth(
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      disabledUntil: (json['disabledUntil'] as num?)?.toInt(),
      lastFailure: failure,
      lastOkAt: (json['lastOkAt'] as num?)?.toInt(),
      lastLatencyMs: (json['lastLatencyMs'] as num?)?.toInt(),
    );
  }
}

/// Provider-level failover: what new-api calls channel management, running
/// inside the client.
///
/// Keys rotate *within* a provider (see [planAiKeyAttempts]); this decides
/// which providers to try, in what order, based on recent health. State is
/// in-memory — persist [snapshotJson] if you want cooldowns to survive a
/// restart.
///
/// Design constraints, deliberate:
/// - The user's explicit choice is always attempt #1, even while cooling
///   down. Health only reorders/filters *fallbacks*, it never overrides
///   intent.
/// - This class plans and records; it performs no I/O and never switches
///   silently. Hosts surface which provider actually served a request.
class AiProviderFailoverRouter {
  AiProviderFailoverRouter(
    this.center, {
    this.policy = const AiKeyRotationPolicy(failureThreshold: 2),
  });

  final AiProviderCenter center;

  /// Provider-level reuse of the key policy: same failure classes, same
  /// cooldown durations. Threshold defaults to 2 — benching a whole provider
  /// should trip faster than benching one of its keys.
  final AiKeyRotationPolicy policy;

  final Map<String, AiProviderHealth> _health = {};

  AiProviderHealth healthOf(String providerId) =>
      _health[providerId] ?? const AiProviderHealth();

  /// Ordered provider ids to try.
  ///
  /// First the effective primary (user intent, resolved exactly like every
  /// feature slot does today). Then, when [includeFallbacks] is on, the other
  /// enabled providers that pass [accept]: healthy ones first in registry
  /// order, cooling ones last by soonest recovery, capped at [maxProviders].
  List<String> planProviderChain({
    String? preferredId,
    bool Function(AiProviderMeta meta)? accept,
    bool includeFallbacks = false,
    int maxProviders = 3,
    int? nowMs,
  }) {
    final primary = center.resolveEffectiveProviderId(
      preferredId: preferredId,
      accept: accept,
    );
    if (!includeFallbacks || maxProviders <= 1) return [primary];

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;

    final healthy = <String>[];
    final cooling = <String>[];
    for (final provider in center.providers) {
      if (provider.id == primary) continue;
      if (!provider.enabled) continue;
      if (accept != null && !accept(provider)) continue;
      (healthOf(provider.id).coolingDownAt(now) ? cooling : healthy)
          .add(provider.id);
    }
    cooling.sort(
      (a, b) => (healthOf(a).disabledUntil ?? 0)
          .compareTo(healthOf(b).disabledUntil ?? 0),
    );

    return [primary, ...healthy, ...cooling].take(maxProviders).toList();
  }

  void recordSuccess(String providerId, {int? latencyMs, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _health[providerId] = AiProviderHealth(
      consecutiveFailures: 0,
      disabledUntil: null,
      lastFailure: null,
      lastOkAt: now,
      lastLatencyMs: latencyMs ?? healthOf(providerId).lastLatencyMs,
    );
  }

  void recordFailure(
    String providerId,
    AiProviderTestFailure failure, {
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final current = healthOf(providerId);
    final nextConsecutive = current.consecutiveFailures + 1;

    int? disabledUntil = current.disabledUntil;
    if (isAiKeyCooldownWorthy(failure) &&
        nextConsecutive >= policy.failureThreshold) {
      disabledUntil = now + policy.cooldownFor(failure).inMilliseconds;
    }

    _health[providerId] = AiProviderHealth(
      consecutiveFailures: nextConsecutive,
      disabledUntil: disabledUntil,
      lastFailure: failure,
      lastOkAt: current.lastOkAt,
      lastLatencyMs: current.lastLatencyMs,
    );
  }

  Map<String, dynamic> snapshotJson() => {
        for (final entry in _health.entries) entry.key: entry.value.toJson(),
      };

  void restoreSnapshot(Map<String, dynamic> snapshot) {
    _health.clear();
    for (final entry in snapshot.entries) {
      final value = entry.value;
      if (value is Map) {
        _health[entry.key] = AiProviderHealth.fromJson(
          value.map((k, v) => MapEntry('$k', v)),
        );
      }
    }
  }
}
