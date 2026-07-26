import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

/// LangChain-facing view of an [AiEndpointConfig].
///
/// Provider management (parsing, base-URL derivation, merging) lives in
/// `ai_provider_kit`; this type adds only the mapping onto LangChain's option
/// objects, so swapping client stacks does not touch provider handling.
class LangchainAiConfig {
  LangchainAiConfig({
    required this.identifier,
    required this.model,
    required this.apiKey,
    this.baseUrl,
    Map<String, String>? headers,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.maxOutputTokens,
    this.thinkingMode = AiThinkingMode.off,
    this.includeThoughts = false,
    this.responsesUsePreviousResponseId,
    this.responsesRequestReasoningSummary,
    this.additional,
  }) : headers = Map.unmodifiable(headers ?? const {});

  /// Maps a provider meta to the registry identifier used by LangchainAiRegistry.
  static String registryIdentifierForProvider(AiProviderMeta? meta) =>
      registryIdentifierForAiProvider(meta);

  final String identifier;
  final String model;
  final String apiKey;
  final String? baseUrl;
  final Map<String, String> headers;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final int? maxOutputTokens;

  /// Cherry-style thinking level.
  final AiThinkingMode thinkingMode;

  /// Gemini thought summary toggle.
  final bool includeThoughts;

  /// Responses API: whether to use server-side conversation state via
  /// `previous_response_id` for tool-output continuation.
  ///
  /// Some third-party "Responses-compatible" gateways do not support this
  /// parameter; turn this off for compatibility.
  final bool? responsesUsePreviousResponseId;

  /// Responses API: whether to request provider reasoning summary output.
  ///
  /// This controls the request-side `reasoning` parameter (e.g. `summary:auto`).
  /// Some third-party gateways may reject it.
  final bool? responsesRequestReasoningSummary;

  final Map<String, dynamic>? additional;

  ChatOpenAIOptions toOpenAIOptions() {
    ChatOpenAIReasoningEffort? effort;
    switch (thinkingMode) {
      case AiThinkingMode.off:
        effort = null;
        break;
      case AiThinkingMode.auto:
        effort = null;
        break;
      case AiThinkingMode.minimal:
        effort = ChatOpenAIReasoningEffort.minimal;
        break;
      case AiThinkingMode.low:
        effort = ChatOpenAIReasoningEffort.low;
        break;
      case AiThinkingMode.medium:
        effort = ChatOpenAIReasoningEffort.medium;
        break;
      case AiThinkingMode.high:
        effort = ChatOpenAIReasoningEffort.high;
        break;
    }

    final url = (baseUrl ?? '').toLowerCase();
    final imageUrlFormat = url.contains('volces.com/api/v3')
        ? OpenAiImageUrlFormat.rawBase64
        : OpenAiImageUrlFormat.dataUrl;

    return ChatOpenAIOptions(
      model: model.isEmpty ? null : model,
      reasoningEffort: effort,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      imageUrlFormat: imageUrlFormat,
    );
  }

  ChatAnthropicOptions toAnthropicOptions() {
    ChatAnthropicThinking? thinking;

    // Anthropic thinking is opt-in. We map Cherry-style thinkingMode into
    // Claude extended thinking budget.
    switch (thinkingMode) {
      case AiThinkingMode.off:
        thinking = ChatAnthropicThinking.disabled();
        break;
      case AiThinkingMode.auto:
        thinking = ChatAnthropicThinking.enabled(budgetTokens: 4096);
        break;
      case AiThinkingMode.minimal:
        thinking = ChatAnthropicThinking.enabled(budgetTokens: 1024);
        break;
      case AiThinkingMode.low:
        thinking = ChatAnthropicThinking.enabled(budgetTokens: 2048);
        break;
      case AiThinkingMode.medium:
        thinking = ChatAnthropicThinking.enabled(budgetTokens: 4096);
        break;
      case AiThinkingMode.high:
        thinking = ChatAnthropicThinking.enabled(budgetTokens: 8192);
        break;
    }

    return ChatAnthropicOptions(
      model: model.isEmpty ? null : model,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinking: thinking,
    );
  }

  ChatGoogleGenerativeAIOptions toGoogleOptions() {
    return ChatGoogleGenerativeAIOptions(
      model: model.isEmpty ? null : model,
      temperature: temperature,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
    );
  }

  factory LangchainAiConfig.fromPrefs(
    String identifier,
    Map<String, String> raw,
  ) {
    return LangchainAiConfig.fromEndpoint(
      AiEndpointConfig.fromRawConfig(identifier, raw),
    );
  }

  factory LangchainAiConfig.fromEndpoint(AiEndpointConfig endpoint) {
    return LangchainAiConfig(
      identifier: endpoint.identifier,
      model: endpoint.model,
      apiKey: endpoint.apiKey,
      baseUrl: endpoint.baseUrl,
      headers: endpoint.headers,
      temperature: endpoint.temperature,
      topP: endpoint.topP,
      maxTokens: endpoint.maxTokens,
      maxOutputTokens: endpoint.maxOutputTokens,
      thinkingMode: endpoint.thinkingMode,
      includeThoughts: endpoint.includeThoughts,
      responsesUsePreviousResponseId: endpoint.responsesUsePreviousResponseId,
      responsesRequestReasoningSummary:
          endpoint.responsesRequestReasoningSummary,
      additional: endpoint.additional,
    );
  }

  AiEndpointConfig toEndpoint() {
    return AiEndpointConfig(
      identifier: identifier,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      headers: headers,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      maxOutputTokens: maxOutputTokens,
      thinkingMode: thinkingMode,
      includeThoughts: includeThoughts,
      responsesUsePreviousResponseId: responsesUsePreviousResponseId,
      responsesRequestReasoningSummary: responsesRequestReasoningSummary,
      additional: additional,
    );
  }

  LangchainAiConfig copyWith({
    String? model,
    String? apiKey,
    String? baseUrl,
    Map<String, String>? headers,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxOutputTokens,
    AiThinkingMode? thinkingMode,
    bool? includeThoughts,
    bool? responsesUsePreviousResponseId,
    bool? responsesRequestReasoningSummary,
    Map<String, dynamic>? additional,
  }) {
    return LangchainAiConfig(
      identifier: identifier,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      headers: headers ?? this.headers,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      includeThoughts: includeThoughts ?? this.includeThoughts,
      responsesUsePreviousResponseId:
          responsesUsePreviousResponseId ?? this.responsesUsePreviousResponseId,
      responsesRequestReasoningSummary: responsesRequestReasoningSummary ??
          this.responsesRequestReasoningSummary,
      additional: additional ?? this.additional,
    );
  }
}

LangchainAiConfig mergeConfigs(
  LangchainAiConfig base,
  LangchainAiConfig override,
) {
  return LangchainAiConfig.fromEndpoint(
    base.toEndpoint().mergedWith(override.toEndpoint()),
  );
}
