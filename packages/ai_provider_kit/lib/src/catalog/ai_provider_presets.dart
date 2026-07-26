import '../config/ai_endpoint_config.dart';
import '../models/ai_provider_meta.dart';

/// Rough deployment region, used to order the catalog for a given audience.
enum AiProviderRegion {
  /// Reachable worldwide.
  global,

  /// Mainland-China hosted endpoints.
  china,

  /// Runs on the user's own machine.
  local,
}

/// A ready-to-use provider entry: endpoint, sane defaults, and where to get a
/// key.
///
/// [defaultUrl] is the full operation URL rather than a bare base, because
/// that is what users copy out of provider docs. Use [baseUrl] when a client
/// needs the base.
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultUrl,
    required this.region,
    this.defaultModel,
    this.apiKeyUrl,
    this.docsUrl,
    this.requiresApiKey = true,
    String? logoKey,
  }) : logoKey = logoKey ?? id;

  /// Stable identifier, also used as the stored provider id for built-ins.
  final String id;

  /// Display name. This package ships no localization; localize in the host app
  /// if you need to.
  final String name;
  final AiProviderType type;

  /// Full operation URL, e.g. `https://api.openai.com/v1/chat/completions`.
  final String defaultUrl;

  /// Seed model for first run only — the live model list is the source of
  /// truth, so this is intentionally absent where a stable default is unclear.
  final String? defaultModel;

  /// Where a user goes to obtain an API key. Surfacing this removes most of
  /// the friction of adding a new provider.
  final String? apiKeyUrl;
  final String? docsUrl;
  final AiProviderRegion region;

  /// False for local runtimes that accept any key.
  final bool requiresApiKey;

  /// Icon key for the host app to map onto its own assets.
  final String logoKey;

  /// [defaultUrl] with operation suffixes stripped.
  String? get baseUrl => deriveAiBaseUrl(defaultUrl);

  /// Provider metadata for this preset, marked as built-in.
  AiProviderMeta toMeta({required int now, bool enabled = false}) {
    return AiProviderMeta(
      id: id,
      name: name,
      type: type,
      enabled: enabled,
      isBuiltIn: true,
      createdAt: now,
      updatedAt: now,
      logoKey: logoKey,
    );
  }
}

/// Built-in provider catalog.
///
/// Entries are data only: adding one is a single const literal, and nothing
/// here is required — a host app can ignore the catalog entirely and register
/// custom providers instead.
abstract final class AiProviderPresets {
  /// OpenAI Chat Completions.
  static const openai = AiProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.openai.com/v1/chat/completions',
    defaultModel: 'gpt-4o-mini',
    apiKeyUrl: 'https://platform.openai.com/api-keys',
    docsUrl: 'https://platform.openai.com/docs/api-reference',
    region: AiProviderRegion.global,
  );

  /// OpenAI Responses API.
  static const openaiResponses = AiProviderPreset(
    id: 'openai-responses',
    name: 'OpenAI Responses',
    type: AiProviderType.openaiResponses,
    defaultUrl: 'https://api.openai.com/v1/responses',
    defaultModel: 'gpt-5-mini',
    apiKeyUrl: 'https://platform.openai.com/api-keys',
    docsUrl: 'https://platform.openai.com/docs/api-reference/responses',
    region: AiProviderRegion.global,
    logoKey: 'openai',
  );

  static const claude = AiProviderPreset(
    id: 'claude',
    name: 'Claude',
    type: AiProviderType.anthropic,
    defaultUrl: 'https://api.anthropic.com/v1/messages',
    defaultModel: 'claude-3-5-sonnet-20240620',
    apiKeyUrl: 'https://console.anthropic.com/settings/keys',
    docsUrl: 'https://docs.anthropic.com/en/api',
    region: AiProviderRegion.global,
  );

  static const gemini = AiProviderPreset(
    id: 'gemini',
    name: 'Gemini',
    type: AiProviderType.gemini,
    defaultUrl: 'https://generativelanguage.googleapis.com',
    defaultModel: 'gemini-2.5-flash',
    apiKeyUrl: 'https://aistudio.google.com/apikey',
    docsUrl: 'https://ai.google.dev/gemini-api/docs',
    region: AiProviderRegion.global,
  );

  static const deepseek = AiProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.deepseek.com/v1/chat/completions',
    defaultModel: 'deepseek-chat',
    apiKeyUrl: 'https://platform.deepseek.com/api_keys',
    docsUrl: 'https://api-docs.deepseek.com',
    region: AiProviderRegion.global,
  );

  static const openrouter = AiProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://openrouter.ai/api/v1/chat/completions',
    // OpenRouter namespaces model ids (`openai/gpt-4o-mini`); this bare id is
    // kept because existing installs already store it.
    defaultModel: 'gpt-4o-mini',
    apiKeyUrl: 'https://openrouter.ai/keys',
    docsUrl: 'https://openrouter.ai/docs',
    region: AiProviderRegion.global,
  );

  static const groq = AiProviderPreset(
    id: 'groq',
    name: 'Groq',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.groq.com/openai/v1/chat/completions',
    apiKeyUrl: 'https://console.groq.com/keys',
    docsUrl: 'https://console.groq.com/docs',
    region: AiProviderRegion.global,
  );

  static const xai = AiProviderPreset(
    id: 'xai',
    name: 'xAI',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.x.ai/v1/chat/completions',
    apiKeyUrl: 'https://console.x.ai',
    docsUrl: 'https://docs.x.ai',
    region: AiProviderRegion.global,
  );

  static const mistral = AiProviderPreset(
    id: 'mistral',
    name: 'Mistral',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.mistral.ai/v1/chat/completions',
    apiKeyUrl: 'https://console.mistral.ai/api-keys',
    docsUrl: 'https://docs.mistral.ai',
    region: AiProviderRegion.global,
  );

  static const together = AiProviderPreset(
    id: 'together',
    name: 'Together AI',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.together.xyz/v1/chat/completions',
    apiKeyUrl: 'https://api.together.ai/settings/api-keys',
    docsUrl: 'https://docs.together.ai',
    region: AiProviderRegion.global,
  );

  static const fireworks = AiProviderPreset(
    id: 'fireworks',
    name: 'Fireworks AI',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.fireworks.ai/inference/v1/chat/completions',
    apiKeyUrl: 'https://fireworks.ai/account/api-keys',
    docsUrl: 'https://docs.fireworks.ai',
    region: AiProviderRegion.global,
  );

  static const dashscope = AiProviderPreset(
    id: 'dashscope',
    name: 'Alibaba DashScope',
    type: AiProviderType.openaiCompatible,
    defaultUrl:
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    defaultModel: 'qwen-plus',
    apiKeyUrl: 'https://bailian.console.aliyun.com',
    docsUrl: 'https://help.aliyun.com/zh/model-studio',
    region: AiProviderRegion.china,
  );

  static const siliconflow = AiProviderPreset(
    id: 'siliconflow',
    name: 'SiliconFlow',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.siliconflow.cn/v1/chat/completions',
    apiKeyUrl: 'https://cloud.siliconflow.cn/account/ak',
    docsUrl: 'https://docs.siliconflow.cn',
    region: AiProviderRegion.china,
  );

  static const moonshot = AiProviderPreset(
    id: 'moonshot',
    name: 'Moonshot',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://api.moonshot.cn/v1/chat/completions',
    apiKeyUrl: 'https://platform.moonshot.cn/console/api-keys',
    docsUrl: 'https://platform.moonshot.cn/docs',
    region: AiProviderRegion.china,
  );

  static const zhipu = AiProviderPreset(
    id: 'zhipu',
    name: 'Zhipu AI',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    apiKeyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    docsUrl: 'https://open.bigmodel.cn/dev/api',
    region: AiProviderRegion.china,
  );

  static const volcengineArk = AiProviderPreset(
    id: 'ark',
    name: 'Volcengine Ark',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    apiKeyUrl: 'https://console.volcengine.com/ark',
    docsUrl: 'https://www.volcengine.com/docs/82379',
    region: AiProviderRegion.china,
  );


  /// Self-hosted new-api gateway (43k-star aggregation hub). One token in the
  /// reader fans out to every channel configured server-side.
  static const newApi = AiProviderPreset(
    id: 'newapi',
    name: 'New API (self-hosted)',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'http://localhost:3000/v1/chat/completions',
    docsUrl: 'https://docs.newapi.pro',
    region: AiProviderRegion.local,
  );

  /// Self-hosted CLIProxyAPI: exposes CLI subscriptions (Claude Code, Codex,
  /// Gemini CLI…) as an OpenAI-compatible endpoint. The sanctioned way to use
  /// subscription quota from this app — OAuth wrapping stays on the user's own
  /// machine, not inside a mobile client.
  static const cliProxyApi = AiProviderPreset(
    id: 'cliproxyapi',
    name: 'CLIProxyAPI (self-hosted)',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'http://localhost:8317/v1/chat/completions',
    docsUrl: 'https://github.com/router-for-me/CLIProxyAPI',
    region: AiProviderRegion.local,
  );

  static const ollama = AiProviderPreset(
    id: 'ollama',
    name: 'Ollama',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'http://localhost:11434/v1/chat/completions',
    docsUrl: 'https://github.com/ollama/ollama/blob/main/docs/openai.md',
    region: AiProviderRegion.local,
    requiresApiKey: false,
  );

  static const lmStudio = AiProviderPreset(
    id: 'lmstudio',
    name: 'LM Studio',
    type: AiProviderType.openaiCompatible,
    defaultUrl: 'http://localhost:1234/v1/chat/completions',
    docsUrl: 'https://lmstudio.ai/docs',
    region: AiProviderRegion.local,
    requiresApiKey: false,
  );

  /// Every preset, grouped global → china → local.
  static const List<AiProviderPreset> all = [
    openai,
    openaiResponses,
    claude,
    gemini,
    deepseek,
    openrouter,
    groq,
    xai,
    mistral,
    together,
    fireworks,
    dashscope,
    siliconflow,
    moonshot,
    zhipu,
    volcengineArk,
    newApi,
    cliProxyApi,
    ollama,
    lmStudio,
  ];

  static AiProviderPreset? byId(String id) {
    final needle = id.trim();
    for (final preset in all) {
      if (preset.id == needle) return preset;
    }
    return null;
  }

  static List<AiProviderPreset> inRegion(AiProviderRegion region) {
    return all.where((p) => p.region == region).toList(growable: false);
  }
}
