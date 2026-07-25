import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

AiProviderMeta meta(
  String id, {
  bool enabled = true,
  bool isBuiltIn = false,
  AiProviderType type = AiProviderType.openaiCompatible,
  String? name,
}) {
  return AiProviderMeta(
    id: id,
    name: name ?? id,
    type: type,
    enabled: enabled,
    isBuiltIn: isBuiltIn,
    createdAt: 1,
    updatedAt: 1,
  );
}

void main() {
  late MemoryAiProviderStore store;
  late AiProviderCenter center;

  setUp(() {
    store = MemoryAiProviderStore();
    center = AiProviderCenter(store);
  });

  group('registry', () {
    test('seeds built-ins when empty', () {
      expect(center.hasProviders, isFalse);
      center.ensureInitialized(builtIns: [meta('openai'), meta('claude')]);
      expect(center.providers.map((p) => p.id), ['openai', 'claude']);
    });

    test('refreshes built-in display fields but keeps the user toggle', () {
      center.providers = [
        meta('openai', enabled: true, name: 'Old Name', isBuiltIn: true),
      ];

      center.ensureInitialized(builtIns: [
        meta('openai', enabled: false, name: 'OpenAI', isBuiltIn: true),
      ]);

      final openai = center.providerById('openai')!;
      expect(openai.name, 'OpenAI', reason: 'display fields refresh');
      expect(openai.enabled, isTrue, reason: 'user toggle must survive');
    });

    test('keeps custom providers after the built-ins', () {
      center.providers = [meta('mine'), meta('openai', isBuiltIn: true)];
      center.ensureInitialized(builtIns: [meta('openai', isBuiltIn: true)]);
      expect(center.providers.map((p) => p.id), ['openai', 'mine']);
    });

    test('upsert then delete', () {
      center.upsertProvider(meta('a'));
      center.upsertProvider(meta('b'));
      center.upsertProvider(meta('a', name: 'renamed'));

      expect(center.providers.length, 2);
      expect(center.providerById('a')!.name, 'renamed');

      center.deleteProvider('a');
      expect(center.providerById('a'), isNull);
      expect(center.providers.map((p) => p.id), ['b']);
    });

    test('survives a corrupt registry value and reports it', () {
      Object? reported;
      final guarded = AiProviderCenter(
        MemoryAiProviderStore({AiProviderCenter.providersKey: 'not json'}),
        onDecodeError: (error, _) => reported = error,
      );

      expect(guarded.providers, isEmpty);
      expect(reported, isNotNull);
    });
  });

  group('configuration', () {
    test('round-trips and deletes together with caches', () {
      center.saveConfig('openai', {'api_key': 'sk', 'model': 'gpt-4o-mini'});
      center.saveModelsCache('openai', ['b', 'a']);
      center.saveModelCapabilitiesCache('openai', [
        const AiModelCapability(id: 'a', contextWindow: 128000),
      ]);

      expect(center.configOf('openai'), {
        'api_key': 'sk',
        'model': 'gpt-4o-mini',
      });
      expect(center.modelsCache('openai')!.models, ['a', 'b']);
      expect(center.modelCapabilitiesCache('openai')!.models.single.id, 'a');

      center.deleteConfig('openai');

      expect(center.configOf('openai'), isEmpty);
      expect(center.modelsCache('openai'), isNull);
      expect(center.modelCapabilitiesCache('openai'), isNull);
    });

    test('model cache is de-duplicated and sorted', () {
      center.saveModelsCache('p', ['b', ' a ', 'b', '', 'c']);
      expect(center.modelsCache('p')!.models, ['a', 'b', 'c']);
    });

    test('capability cache is de-duplicated by id and sorted', () {
      center.saveModelCapabilitiesCache('p', const [
        AiModelCapability(id: 'b'),
        AiModelCapability(id: ' '),
        AiModelCapability(id: 'a', contextWindow: 1),
        AiModelCapability(id: 'a', contextWindow: 2),
      ]);

      final cached = center.modelCapabilitiesCache('p')!.models;
      expect(cached.map((e) => e.id), ['a', 'b']);
      expect(cached.first.contextWindow, 2, reason: 'last entry wins');
    });

    test('safeConfig strips only secrets', () {
      final safe = AiProviderCenter.safeConfig({
        'api_key': 'sk',
        'api_keys': '[]',
        'url': 'https://host',
        'model': 'm',
      });
      expect(safe, {'url': 'https://host', 'model': 'm'});
    });

    test('uses the documented storage keys', () {
      center.saveConfig('openai', {'model': 'm'});
      center.defaultProviderId = 'claude';
      center.saveModelsCache('openai', ['m']);

      expect(store.values.keys, containsAll(<String>[
        'aiConfig_openai',
        'selectedAiService',
        'aiModelsCacheV1_openai',
      ]));
    });

    test('default provider falls back to openai', () {
      expect(center.defaultProviderId, 'openai');
      center.defaultProviderId = 'gemini';
      expect(center.defaultProviderId, 'gemini');
    });
  });

  group('resolveEffectiveProviderId', () {
    test('prefers the feature choice when it is enabled', () {
      center.providers = [meta('openai'), meta('claude')];
      center.defaultProviderId = 'openai';
      expect(
        center.resolveEffectiveProviderId(preferredId: 'claude'),
        'claude',
      );
    });

    test('falls back to the default provider when the choice is disabled', () {
      center.providers = [meta('openai'), meta('claude', enabled: false)];
      center.defaultProviderId = 'openai';
      expect(center.resolveEffectiveProviderId(preferredId: 'claude'), 'openai');
      expect(center.resolveEffectiveProviderId(preferredId: ''), 'openai');
      expect(center.resolveEffectiveProviderId(), 'openai');
    });

    test('falls back to the first enabled provider', () {
      center.providers = [
        meta('openai', enabled: false),
        meta('gemini', enabled: false),
        meta('claude'),
      ];
      center.defaultProviderId = 'openai';
      expect(center.resolveEffectiveProviderId(preferredId: 'gemini'), 'claude');
    });

    test('returns a usable id even when nothing is enabled', () {
      center.providers = [meta('openai', enabled: false)];
      center.defaultProviderId = 'openai';
      expect(center.resolveEffectiveProviderId(preferredId: 'nope'), 'openai');

      final empty = AiProviderCenter(
        MemoryAiProviderStore({AiProviderCenter.defaultProviderKey: ''}),
      );
      expect(empty.resolveEffectiveProviderId(preferredId: 'only'), 'only');
    });

    test('accept filters embeddings-capable providers at every step', () {
      // Anthropic and Gemini cannot serve OpenAI-style embeddings, so a feature
      // that needs them must skip an otherwise-enabled preferred provider.
      center.providers = [
        meta('claude', type: AiProviderType.anthropic),
        meta('gemini', type: AiProviderType.gemini),
        meta('siliconflow'),
      ];
      center.defaultProviderId = 'claude';

      expect(
        center.resolveEffectiveProviderId(
          preferredId: 'gemini',
          accept: AiProviderCenter.acceptsOpenAiCompatible,
        ),
        'siliconflow',
      );

      // Without the filter, the preferred provider wins as usual.
      expect(
        center.resolveEffectiveProviderId(preferredId: 'gemini'),
        'gemini',
      );
    });

    test('accept still honours a qualifying preferred provider', () {
      center.providers = [
        meta('openai'),
        meta('claude', type: AiProviderType.anthropic),
      ];
      center.defaultProviderId = 'claude';
      expect(
        center.resolveEffectiveProviderId(
          preferredId: 'openai',
          accept: AiProviderCenter.acceptsOpenAiCompatible,
        ),
        'openai',
      );
    });
  });
}
