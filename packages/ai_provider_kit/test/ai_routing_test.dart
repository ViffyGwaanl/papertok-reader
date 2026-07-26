import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

AiApiKeyEntry key(
  String id, {
  bool enabled = true,
  int? disabledUntil,
  int consecutiveFailures = 0,
}) {
  return AiApiKeyEntry(
    id: id,
    name: id,
    key: 'sk-$id',
    enabled: enabled,
    createdAt: 1,
    updatedAt: 1,
    consecutiveFailures: consecutiveFailures,
    disabledUntil: disabledUntil,
  );
}

AiProviderMeta meta(
  String id, {
  bool enabled = true,
  AiProviderType type = AiProviderType.openaiCompatible,
}) {
  return AiProviderMeta(
    id: id,
    name: id,
    type: type,
    enabled: enabled,
    isBuiltIn: false,
    createdAt: 1,
    updatedAt: 1,
  );
}

const now = 1000000;

void main() {
  group('AiKeyRotationPolicy.fromRawConfig', () {
    test('defaults and clamps mirror the shipped behaviour', () {
      const defaults = AiKeyRotationPolicy();
      expect(defaults.failureThreshold, 3);
      expect(defaults.authCooldown, const Duration(minutes: 60));
      expect(defaults.rateLimitCooldown, const Duration(minutes: 5));
      expect(defaults.serviceCooldown, const Duration(minutes: 1));

      final parsed = AiKeyRotationPolicy.fromRawConfig({
        'api_key_policy_failure_threshold': '99',
        'api_key_policy_auth_cooldown_min': '0',
        'api_key_policy_rate_limit_cooldown_min': '10',
      });
      expect(parsed.failureThreshold, 10, reason: 'clamped to 1..10');
      expect(parsed.authCooldown, const Duration(minutes: 1),
          reason: 'clamped to >=1min');
      expect(parsed.rateLimitCooldown, const Duration(minutes: 10));
    });

    test('cooldown duration depends on the failure class', () {
      const policy = AiKeyRotationPolicy();
      expect(policy.cooldownFor(AiProviderTestFailure.unauthorized),
          const Duration(minutes: 60));
      expect(policy.cooldownFor(AiProviderTestFailure.rateLimited),
          const Duration(minutes: 5));
      expect(policy.cooldownFor(AiProviderTestFailure.serverError),
          const Duration(minutes: 1));
    });
  });

  group('classifyAiFailureText', () {
    test('matches the historical string heuristics', () {
      expect(classifyAiFailureText(Exception('HTTP 401 Unauthorized')),
          AiProviderTestFailure.unauthorized);
      expect(classifyAiFailureText('invalid api key provided'),
          AiProviderTestFailure.unauthorized);
      expect(classifyAiFailureText('429 rate limit exceeded'),
          AiProviderTestFailure.rateLimited);
      expect(classifyAiFailureText('503 bad gateway'),
          AiProviderTestFailure.serverError);
      expect(classifyAiFailureText('TimeoutException after 30s'),
          AiProviderTestFailure.unknown);
    });

    test('network/timeout never bench a key', () {
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.unauthorized), isTrue);
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.rateLimited), isTrue);
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.serverError), isTrue);
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.timeout), isFalse);
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.network), isFalse);
      expect(isAiKeyCooldownWorthy(AiProviderTestFailure.unknown), isFalse);
    });
  });

  group('planAiKeyAttempts', () {
    test('skips cooling keys while any key is available', () {
      final attempts = planAiKeyAttempts(
        entries: [key('a', disabledUntil: now + 1), key('b'), key('c')],
        fallbackApiKey: '',
        nowMs: now,
      );
      expect(attempts.map((a) => a.entry!.id), ['b', 'c']);
    });

    test('all cooling → still tries everyone, soonest recovery first', () {
      final attempts = planAiKeyAttempts(
        entries: [
          key('late', disabledUntil: now + 500),
          key('soon', disabledUntil: now + 100),
        ],
        fallbackApiKey: '',
        nowMs: now,
      );
      expect(attempts.map((a) => a.entry!.id), ['soon', 'late']);
    });

    test('round-robin cursor rotates the start', () {
      final attempts = planAiKeyAttempts(
        entries: [key('a'), key('b'), key('c')],
        fallbackApiKey: '',
        startIndex: 1,
        nowMs: now,
      );
      expect(attempts.map((a) => a.entry!.id), ['b', 'c', 'a']);
    });

    test('no managed list → single fallback key; nothing at all → empty', () {
      final single = planAiKeyAttempts(
        entries: const [],
        fallbackApiKey: ' sk-solo ',
        nowMs: now,
      );
      expect(single.single.apiKey, 'sk-solo');
      expect(single.single.entry, isNull);

      expect(
        planAiKeyAttempts(entries: const [], fallbackApiKey: ' ', nowMs: now),
        isEmpty,
      );
    });

    test('disabled keys never participate', () {
      final attempts = planAiKeyAttempts(
        entries: [key('off', enabled: false), key('on')],
        fallbackApiKey: '',
        nowMs: now,
      );
      expect(attempts.map((a) => a.entry!.id), ['on']);
    });
  });

  group('applyAiKeySuccess / applyAiKeyFailure', () {
    const policy = AiKeyRotationPolicy();

    test('success resets streak and actually clears the cooldown', () {
      final updated = applyAiKeySuccess(
        key('a', disabledUntil: now + 999, consecutiveFailures: 5),
        nowMs: now,
      );
      expect(updated.consecutiveFailures, 0);
      expect(updated.disabledUntil, isNull,
          reason: 'the copyWith(disabledUntil: null) no-op bug stays fixed');
      expect(updated.successCount, 1);
      expect(updated.lastSuccessAt, now);
    });

    test('failure benches the key only past the threshold', () {
      var entry = key('a');
      entry = applyAiKeyFailure(entry,
          nowMs: now,
          policy: policy,
          failure: AiProviderTestFailure.rateLimited);
      entry = applyAiKeyFailure(entry,
          nowMs: now,
          policy: policy,
          failure: AiProviderTestFailure.rateLimited);
      expect(entry.disabledUntil, isNull, reason: 'below threshold of 3');

      entry = applyAiKeyFailure(entry,
          nowMs: now,
          policy: policy,
          failure: AiProviderTestFailure.rateLimited);
      expect(entry.consecutiveFailures, 3);
      expect(entry.disabledUntil, now + 5 * 60 * 1000,
          reason: 'rate-limit class → 5min cooldown');
      expect(entry.failureCount, 3);
    });

    test('timeouts count as failures but never set a cooldown', () {
      var entry = key('a', consecutiveFailures: 9);
      entry = applyAiKeyFailure(entry,
          nowMs: now, policy: policy, failure: AiProviderTestFailure.timeout);
      expect(entry.consecutiveFailures, 10);
      expect(entry.disabledUntil, isNull);
    });

    test('clearAiKeyCooldown wipes streak+cooldown but not counters', () {
      final entry = key('a', disabledUntil: now + 999, consecutiveFailures: 4)
          .copyWith(failureCount: 7, successCount: 2);
      final cleared = clearAiKeyCooldown(entry, nowMs: now);
      expect(cleared.consecutiveFailures, 0);
      expect(cleared.disabledUntil, isNull);
      expect(cleared.failureCount, 7);
      expect(cleared.successCount, 2);
      expect(cleared.updatedAt, now);
    });

    test('upsertAiKeyEntry replaces by id and ignores strangers', () {
      final list = [key('a'), key('b')];
      final updated = upsertAiKeyEntry(list, key('b', consecutiveFailures: 7));
      expect(updated[1].consecutiveFailures, 7);
      expect(upsertAiKeyEntry(list, key('zz')), same(list));
    });
  });

  group('AiProviderFailoverRouter', () {
    late AiProviderCenter center;
    late AiProviderFailoverRouter router;

    setUp(() {
      center = AiProviderCenter(MemoryAiProviderStore());
      center.providers = [
        meta('openai'),
        meta('deepseek'),
        meta('siliconflow'),
        meta('claude', type: AiProviderType.anthropic),
        meta('disabled', enabled: false),
      ];
      center.defaultProviderId = 'openai';
      router = AiProviderFailoverRouter(center);
    });

    test('without fallbacks it is exactly the effective resolution', () {
      expect(router.planProviderChain(preferredId: 'deepseek'), ['deepseek']);
    });

    test('fallbacks follow registry order, disabled excluded, capped', () {
      final chain = router.planProviderChain(
        preferredId: 'deepseek',
        includeFallbacks: true,
        maxProviders: 3,
        nowMs: now,
      );
      expect(chain, ['deepseek', 'openai', 'siliconflow']);
    });

    test('accept filter applies to fallbacks too', () {
      final chain = router.planProviderChain(
        preferredId: 'openai',
        includeFallbacks: true,
        maxProviders: 4,
        accept: AiProviderCenter.acceptsOpenAiCompatible,
        nowMs: now,
      );
      expect(chain, isNot(contains('claude')));
    });

    test('cooling providers sort last and recover by timestamp', () {
      // Threshold is 2 for providers: two failures bench deepseek.
      router.recordFailure('deepseek', AiProviderTestFailure.serverError,
          nowMs: now);
      router.recordFailure('deepseek', AiProviderTestFailure.serverError,
          nowMs: now);
      expect(router.healthOf('deepseek').coolingDownAt(now + 1), isTrue);

      final chain = router.planProviderChain(
        preferredId: 'openai',
        includeFallbacks: true,
        maxProviders: 4,
        nowMs: now + 1,
      );
      expect(chain.indexOf('deepseek'), greaterThan(chain.indexOf('siliconflow')));

      // The user's explicit choice is never blocked by its own cooldown.
      final explicit = router.planProviderChain(
        preferredId: 'deepseek',
        includeFallbacks: true,
        maxProviders: 2,
        nowMs: now + 1,
      );
      expect(explicit.first, 'deepseek');
    });

    test('success heals the provider; snapshot round-trips', () {
      router.recordFailure('deepseek', AiProviderTestFailure.rateLimited,
          nowMs: now);
      router.recordFailure('deepseek', AiProviderTestFailure.rateLimited,
          nowMs: now);
      router.recordSuccess('deepseek', latencyMs: 240, nowMs: now + 10);

      expect(router.healthOf('deepseek').coolingDownAt(now + 11), isFalse);
      expect(router.healthOf('deepseek').lastLatencyMs, 240);

      router.recordFailure('openai', AiProviderTestFailure.unauthorized,
          nowMs: now);
      final restored = AiProviderFailoverRouter(center)
        ..restoreSnapshot(router.snapshotJson());
      expect(restored.healthOf('openai').consecutiveFailures, 1);
      expect(restored.healthOf('openai').lastFailure,
          AiProviderTestFailure.unauthorized);
      expect(restored.healthOf('deepseek').lastLatencyMs, 240);
    });

    test('timeout failures never bench a provider either', () {
      router.recordFailure('openai', AiProviderTestFailure.timeout, nowMs: now);
      router.recordFailure('openai', AiProviderTestFailure.timeout, nowMs: now);
      router.recordFailure('openai', AiProviderTestFailure.timeout, nowMs: now);
      expect(router.healthOf('openai').coolingDownAt(now + 1), isFalse);
    });
  });

  group('gateway presets', () {
    test('official default ports, local region, openai-compatible', () {
      expect(AiProviderPresets.newApi.defaultUrl,
          'http://localhost:3000/v1/chat/completions');
      expect(AiProviderPresets.cliProxyApi.defaultUrl,
          'http://localhost:8317/v1/chat/completions');
      for (final p in [AiProviderPresets.newApi, AiProviderPresets.cliProxyApi]) {
        expect(p.region, AiProviderRegion.local);
        expect(p.type, AiProviderType.openaiCompatible);
        expect(AiProviderPresets.byId(p.id), same(p));
      }
    });
  });
}
