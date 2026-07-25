import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';

/// The built-in provider list is persisted into user installs (ids become
/// stored provider ids, urls/models become their initial config). This locks
/// the exact tuples so sourcing them from `ai_provider_kit` cannot silently
/// repoint anyone.
void main() {
  test('built-in AI services keep their exact identifiers and defaults', () {
    final services = buildDefaultAiServices();

    expect(services.length, 6);
    expect(
      services.map((s) => s.identifier).toList(),
      ['openai', 'openai-responses', 'claude', 'gemini', 'deepseek', 'openrouter'],
    );

    void expectOption(
      int index, {
      required String title,
      required String logo,
      required String url,
      required String model,
    }) {
      final option = services[index];
      expect(option.title, title, reason: 'title at $index');
      expect(option.logo, logo, reason: 'logo at $index');
      expect(option.defaultUrl, url, reason: 'url at $index');
      expect(option.defaultModel, model, reason: 'model at $index');
      expect(option.defaultApiKey, 'YOUR_API_KEY', reason: 'key at $index');
    }

    // Tests run without the store flags, so the OpenAI branch is active.
    expectOption(
      0,
      title: 'OpenAI',
      logo: 'assets/images/openai.png',
      url: 'https://api.openai.com/v1/chat/completions',
      model: 'gpt-4o-mini',
    );
    expectOption(
      1,
      title: 'OpenAI Responses',
      logo: 'assets/images/openai.png',
      url: 'https://api.openai.com/v1/responses',
      model: 'gpt-5-mini',
    );
    expectOption(
      2,
      title: 'Claude',
      logo: 'assets/images/claude.png',
      url: 'https://api.anthropic.com/v1/messages',
      model: 'claude-3-5-sonnet-20240620',
    );
    expectOption(
      3,
      title: 'Gemini',
      logo: 'assets/images/gemini.png',
      url: 'https://generativelanguage.googleapis.com',
      model: 'gemini-2.5-flash',
    );
    expectOption(
      4,
      title: 'DeepSeek',
      logo: 'assets/images/deepseek.png',
      url: 'https://api.deepseek.com/v1/chat/completions',
      model: 'deepseek-chat',
    );
    expectOption(
      5,
      title: 'OpenRouter',
      logo: 'assets/images/openrouter.png',
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: 'gpt-4o-mini',
    );
  });

  test('generic slot endpoint is unchanged', () {
    // The 通用 branch (mainland store builds) reuses this URL under the
    // `openai` identifier; it cannot be reached from tests because the flag is
    // compile-time, so assert the value it depends on.
    expect(
      AiProviderPresets.dashscope.defaultUrl,
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    );
  });
}
