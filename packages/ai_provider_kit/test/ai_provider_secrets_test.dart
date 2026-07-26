import 'dart:convert';

import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

AiProviderMeta meta(String id) => AiProviderMeta(
      id: id,
      name: id,
      type: AiProviderType.openaiCompatible,
      enabled: true,
      isBuiltIn: false,
      createdAt: 1,
      updatedAt: 1,
    );

/// A keystore that accepts writes and loses them, like a misconfigured
/// platform keychain.
class BrokenSecretStore extends MemoryAiProviderStore {
  @override
  bool get hasSecureSecretChannel => true;

  @override
  String? readSecret(String key) => null;

  @override
  void writeSecret(String key, String value) {}

  @override
  void removeSecret(String key) {}
}

void main() {
  group('plain store (default)', () {
    test('keeps the existing single-blob layout untouched', () {
      final store = MemoryAiProviderStore();
      final center = AiProviderCenter(store)..providers = [meta('openai')];

      center.saveConfig('openai', {'api_key': 'sk', 'model': 'm'});

      final raw = jsonDecode(store.values['aiConfig_openai']!) as Map;
      expect(raw['api_key'], 'sk', reason: 'no layout change without a keystore');
      expect(store.values.containsKey('aiSecretV1_openai'), isFalse);
      expect(center.configOf('openai'), {'api_key': 'sk', 'model': 'm'});
    });

    test('migration is a no-op and reports nothing', () {
      final center = AiProviderCenter(MemoryAiProviderStore())
        ..providers = [meta('openai')];
      center.saveConfig('openai', {'api_key': 'sk'});

      expect(center.migrateSecretsToSecureChannel(), isEmpty);
      expect(center.configOf('openai')['api_key'], 'sk');
    });
  });

  group('secure store', () {
    late MemorySecureAiProviderStore store;
    late AiProviderCenter center;

    setUp(() {
      store = MemorySecureAiProviderStore();
      center = AiProviderCenter(store)..providers = [meta('openai')];
    });

    test('keeps secrets out of the plain config entry', () {
      center.saveConfig('openai', {
        'api_key': 'sk-secret',
        'api_keys': '["k1","k2"]',
        'model': 'gpt-4o-mini',
      });

      final plain = jsonDecode(store.values['aiConfig_openai']!) as Map;
      expect(plain.containsKey('api_key'), isFalse);
      expect(plain.containsKey('api_keys'), isFalse);
      expect(plain['model'], 'gpt-4o-mini');

      // Callers still see one merged map.
      final config = center.configOf('openai');
      expect(config['api_key'], 'sk-secret');
      expect(config['api_keys'], '["k1","k2"]');
      expect(config['model'], 'gpt-4o-mini');
    });

    test('clearing a key removes it from the secret compartment', () {
      center.saveConfig('openai', {'api_key': 'sk', 'model': 'm'});
      expect(store.secrets, isNotEmpty);

      center.saveConfig('openai', {'api_key': '', 'model': 'm'});
      expect(store.secrets, isEmpty);
      expect(center.configOf('openai')['api_key'], anyOf(isNull, isEmpty));
    });

    test('deleting a provider clears its secret too', () {
      center.saveConfig('openai', {'api_key': 'sk'});
      center.deleteConfig('openai');
      expect(store.secrets, isEmpty);
      expect(center.configOf('openai'), isEmpty);
    });

    test('migrates an existing plaintext install', () {
      // Simulate what is already on disk today: secrets inline.
      store.write(
        'aiConfig_openai',
        jsonEncode({'api_key': 'sk-old', 'model': 'm'}),
      );

      expect(center.migrateSecretsToSecureChannel(), ['openai']);

      final plain = jsonDecode(store.values['aiConfig_openai']!) as Map;
      expect(plain.containsKey('api_key'), isFalse,
          reason: 'plaintext copy is dropped');
      expect(store.secrets, isNotEmpty);
      expect(center.configOf('openai')['api_key'], 'sk-old');
      expect(center.configOf('openai')['model'], 'm');
    });

    test('migration is idempotent', () {
      store.write('aiConfig_openai', jsonEncode({'api_key': 'sk-old'}));

      expect(center.migrateSecretsToSecureChannel(), ['openai']);
      expect(center.migrateSecretsToSecureChannel(), isEmpty);
      expect(center.configOf('openai')['api_key'], 'sk-old');
    });

    test('a keystore that silently drops writes loses no keys', () {
      final broken = BrokenSecretStore();
      final guarded = AiProviderCenter(broken)..providers = [meta('openai')];
      broken.write('aiConfig_openai', jsonEncode({'api_key': 'sk-old'}));

      expect(guarded.migrateSecretsToSecureChannel(), isEmpty);

      // The plaintext copy must still be there rather than deleted into a void.
      final plain = jsonDecode(broken.values['aiConfig_openai']!) as Map;
      expect(plain['api_key'], 'sk-old');
    });
  });
}
