import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/utils/env_var.dart';

class AiServiceOption {
  const AiServiceOption({
    required this.identifier,
    required this.title,
    required this.logo,
    required this.defaultUrl,
    required this.defaultApiKey,
    required this.defaultModel,
  });

  final String identifier;
  final String title;
  final String logo;
  final String defaultUrl;
  final String defaultApiKey;
  final String defaultModel;
}

const String _placeholderApiKey = 'YOUR_API_KEY';

/// Bundled artwork, keyed by [AiProviderPreset.logoKey].
const Map<String, String> _logoAssets = {
  'openai': 'assets/images/openai.png',
  'claude': 'assets/images/claude.png',
  'gemini': 'assets/images/gemini.png',
  'deepseek': 'assets/images/deepseek.png',
  'openrouter': 'assets/images/openrouter.png',
};

AiServiceOption _fromPreset(AiProviderPreset preset) {
  return AiServiceOption(
    identifier: preset.id,
    title: preset.name,
    logo: _logoAssets[preset.logoKey] ?? 'assets/images/commonAi.png',
    defaultUrl: preset.defaultUrl,
    defaultApiKey: _placeholderApiKey,
    defaultModel: preset.defaultModel ?? '',
  );
}

/// The provider list shown as built-ins in this app.
///
/// Endpoint data comes from `ai_provider_kit`'s catalog; the catalog is wider
/// than this list on purpose — adding an entry here also needs artwork and a
/// product decision.
List<AiServiceOption> buildDefaultAiServices() {
  return [
    if (!EnvVar.enableOpenAiConfig)
      // Legacy generic slot: keeps the `openai` identifier while pointing at an
      // OpenAI-compatible gateway instead of OpenAI itself.
      AiServiceOption(
        identifier: 'openai',
        title: '通用',
        logo: 'assets/images/commonAi.png',
        defaultUrl: AiProviderPresets.dashscope.defaultUrl,
        defaultApiKey: _placeholderApiKey,
        defaultModel: 'qwen-long',
      )
    else
      _fromPreset(AiProviderPresets.openai),
    _fromPreset(AiProviderPresets.openaiResponses),
    _fromPreset(AiProviderPresets.claude),
    _fromPreset(AiProviderPresets.gemini),
    _fromPreset(AiProviderPresets.deepseek),
    _fromPreset(AiProviderPresets.openrouter),
  ];
}
