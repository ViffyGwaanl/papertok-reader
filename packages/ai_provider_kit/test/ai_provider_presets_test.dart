import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

void main() {
  test('preset ids are unique', () {
    final ids = AiProviderPresets.all.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every preset has a parseable http(s) endpoint', () {
    for (final preset in AiProviderPresets.all) {
      final uri = Uri.tryParse(preset.defaultUrl);
      expect(uri, isNotNull, reason: '${preset.id} has an unparseable URL');
      expect(
        uri!.scheme,
        anyOf('http', 'https'),
        reason: '${preset.id} must use http(s)',
      );
      expect(uri.host, isNotEmpty, reason: '${preset.id} has no host');
    }
  });

  test('remote presets that need a key link to where it is obtained', () {
    for (final preset in AiProviderPresets.all) {
      if (!preset.requiresApiKey) continue;
      // Self-hosted gateways issue their own tokens — no signup URL exists.
      if (preset.region == AiProviderRegion.local) continue;
      expect(
        preset.apiKeyUrl,
        isNotNull,
        reason: '${preset.id} should tell users where to get a key',
      );
    }
  });

  test('local presets point at localhost; local runtimes need no key', () {
    final local = AiProviderPresets.inRegion(AiProviderRegion.local);
    expect(local, isNotEmpty);
    for (final preset in local) {
      expect(Uri.parse(preset.defaultUrl).host, 'localhost');
    }
    expect(AiProviderPresets.ollama.requiresApiKey, isFalse);
    expect(AiProviderPresets.lmStudio.requiresApiKey, isFalse);
  });

  // These six ids are already persisted in installed apps; changing their
  // endpoint or seed model would silently repoint existing users.
  test('legacy built-in presets keep their stored values', () {
    void expectPreset(
      String id, {
      required AiProviderType type,
      required String url,
      required String? model,
    }) {
      final preset = AiProviderPresets.byId(id);
      expect(preset, isNotNull, reason: 'missing preset $id');
      expect(preset!.type, type);
      expect(preset.defaultUrl, url);
      expect(preset.defaultModel, model);
    }

    expectPreset(
      'openai',
      type: AiProviderType.openaiCompatible,
      url: 'https://api.openai.com/v1/chat/completions',
      model: 'gpt-4o-mini',
    );
    expectPreset(
      'openai-responses',
      type: AiProviderType.openaiResponses,
      url: 'https://api.openai.com/v1/responses',
      model: 'gpt-5-mini',
    );
    expectPreset(
      'claude',
      type: AiProviderType.anthropic,
      url: 'https://api.anthropic.com/v1/messages',
      model: 'claude-3-5-sonnet-20240620',
    );
    expectPreset(
      'gemini',
      type: AiProviderType.gemini,
      url: 'https://generativelanguage.googleapis.com',
      model: 'gemini-2.5-flash',
    );
    expectPreset(
      'deepseek',
      type: AiProviderType.openaiCompatible,
      url: 'https://api.deepseek.com/v1/chat/completions',
      model: 'deepseek-chat',
    );
    expectPreset(
      'openrouter',
      type: AiProviderType.openaiCompatible,
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: 'gpt-4o-mini',
    );
  });

  test('baseUrl strips the operation suffix', () {
    expect(AiProviderPresets.openai.baseUrl, 'https://api.openai.com/v1');
    expect(AiProviderPresets.ollama.baseUrl, 'http://localhost:11434/v1');
    expect(
      AiProviderPresets.gemini.baseUrl,
      'https://generativelanguage.googleapis.com',
    );
  });

  test('toMeta produces built-in, disabled-by-default metadata', () {
    final meta = AiProviderPresets.claude.toMeta(now: 42);
    expect(meta.id, 'claude');
    expect(meta.type, AiProviderType.anthropic);
    expect(meta.isBuiltIn, isTrue);
    expect(meta.enabled, isFalse);
    expect(meta.createdAt, 42);
    expect(meta.logoKey, 'claude');
  });
}
