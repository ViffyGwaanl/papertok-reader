import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

AiProviderMeta meta(String id, {bool enabled = true}) => AiProviderMeta(
      id: id,
      name: id,
      type: AiProviderType.openaiCompatible,
      enabled: enabled,
      isBuiltIn: false,
      createdAt: 1,
      updatedAt: 1,
    );

AiProviderCenter seeded() {
  final center = AiProviderCenter(MemoryAiProviderStore());
  center.providers = [meta('openai'), meta('custom')];
  center.defaultProviderId = 'custom';
  center.saveConfig('openai', {
    'url': 'https://api.openai.com/v1/chat/completions',
    'model': 'gpt-4o-mini',
    'api_key': 'sk-secret',
  });
  center.saveConfig('custom', {'url': 'https://gw.example/v1', 'api_keys': '["k1"]'});
  return center;
}

void main() {
  test('export omits secrets by default', () {
    final payload = AiProviderPortfolio.export(seeded());

    expect(payload['containsSecrets'], isFalse);
    expect(payload['defaultProviderId'], 'custom');
    expect((payload['providers'] as List).length, 2);

    final configs = payload['configs'] as Map;
    expect(configs['openai'], isNot(contains('api_key')));
    expect(configs['custom'], isNot(contains('api_keys')));
    expect((configs['openai'] as Map)['model'], 'gpt-4o-mini');
  });

  test('export can include secrets when explicitly asked', () {
    final payload = AiProviderPortfolio.export(seeded(), includeSecrets: true);
    expect(payload['containsSecrets'], isTrue);
    expect((payload['configs'] as Map)['openai']['api_key'], 'sk-secret');
  });

  test('round-trips onto an empty device', () {
    final payload = AiProviderPortfolio.export(seeded(), includeSecrets: true);
    final target = AiProviderCenter(MemoryAiProviderStore());

    final result = AiProviderPortfolio.import(target, payload)!;

    expect(result.imported, ['openai', 'custom']);
    expect(result.secretsIncluded, isTrue);
    expect(target.providers.map((p) => p.id), ['openai', 'custom']);
    expect(target.defaultProviderId, 'custom');
    expect(target.configOf('openai')['api_key'], 'sk-secret');
  });

  test('a secret-free import keeps keys already on the device', () {
    final payload = AiProviderPortfolio.export(seeded());

    final target = AiProviderCenter(MemoryAiProviderStore());
    target.providers = [meta('openai')];
    target.saveConfig('openai', {'api_key': 'sk-local', 'model': 'old'});

    AiProviderPortfolio.import(target, payload);

    final config = target.configOf('openai');
    expect(config['api_key'], 'sk-local', reason: 'local key must survive');
    expect(config['model'], 'gpt-4o-mini', reason: 'non-secrets are updated');
  });

  test('can skip providers that already exist', () {
    final payload = AiProviderPortfolio.export(seeded());
    final target = AiProviderCenter(MemoryAiProviderStore());
    target.providers = [meta('openai')];
    target.saveConfig('openai', {'model': 'keep-me'});

    final result =
        AiProviderPortfolio.import(target, payload, overwriteExisting: false)!;

    expect(result.skipped, ['openai']);
    expect(result.imported, ['custom']);
    expect(target.configOf('openai')['model'], 'keep-me');
  });

  test('rejects payloads it does not understand', () {
    final target = AiProviderCenter(MemoryAiProviderStore());
    expect(AiProviderPortfolio.import(target, {'providers': []}), isNull);
    expect(
      AiProviderPortfolio.import(target, {'schemaVersion': 999, 'providers': []}),
      isNull,
    );
    expect(
      AiProviderPortfolio.import(target, {'schemaVersion': 1, 'providers': 'nope'}),
      isNull,
    );
  });

  test('can leave the default provider alone', () {
    final payload = AiProviderPortfolio.export(seeded());
    final target = AiProviderCenter(MemoryAiProviderStore());
    target.defaultProviderId = 'mine';

    AiProviderPortfolio.import(target, payload, applyDefaultProvider: false);

    expect(target.defaultProviderId, 'mine');
  });
}
