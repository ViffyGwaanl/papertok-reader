import 'dart:convert';

import '../models/ai_provider_meta.dart';
import '../models/ai_thinking_mode.dart';

/// Registry identifier used by client stacks to pick a chat model builder.
///
/// These are stable strings ('openai', 'openai-responses', 'claude', 'gemini')
/// rather than the enum itself, so host apps can key their own factories off
/// them without depending on this package's enum ordering.
String registryIdentifierForAiProvider(AiProviderMeta? meta) {
  if (meta == null) return 'openai';
  return switch (meta.type) {
    AiProviderType.anthropic => 'claude',
    AiProviderType.gemini => 'gemini',
    AiProviderType.openaiResponses => 'openai-responses',
    AiProviderType.openaiCompatible => 'openai',
  };
}

/// Normalized, client-stack agnostic endpoint configuration.
///
/// This is the hand-off point between provider management (this package) and
/// whatever actually talks to the model. It carries no LangChain, Riverpod or
/// Flutter types on purpose — map it onto your client's option objects in the
/// host app.
class AiEndpointConfig {
  AiEndpointConfig({
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

  /// Registry identifier, see [registryIdentifierForAiProvider].
  final String identifier;
  final String model;
  final String apiKey;

  /// API base URL with well-known operation suffixes stripped,
  /// see [deriveAiBaseUrl].
  final String? baseUrl;
  final Map<String, String> headers;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final int? maxOutputTokens;

  /// Requested reasoning/thinking level.
  final AiThinkingMode thinkingMode;

  /// Whether to ask the provider to surface thought summaries (Gemini).
  final bool includeThoughts;

  /// Responses API: use server-side conversation state via
  /// `previous_response_id`. Some third-party gateways do not support it.
  final bool? responsesUsePreviousResponseId;

  /// Responses API: request provider reasoning summary output.
  final bool? responsesRequestReasoningSummary;

  /// Free-form extras passed through from the stored config.
  final Map<String, dynamic>? additional;

  /// Build from the raw string map persisted for a provider.
  factory AiEndpointConfig.fromRawConfig(
    String identifier,
    Map<String, String> raw,
  ) {
    double? parseDouble(String? value) =>
        value == null ? null : double.tryParse(value.trim());
    int? parseInt(String? value) =>
        value == null ? null : int.tryParse(value.trim());

    return AiEndpointConfig(
      identifier: identifier,
      apiKey: raw['api_key'] ?? '',
      model: raw['model'] ?? '',
      baseUrl: deriveAiBaseUrl(raw['url'] ?? ''),
      headers: parseAiHeaders(raw['headers']),
      temperature: parseDouble(raw['temperature']),
      topP: parseDouble(raw['top_p']),
      maxTokens: parseInt(raw['max_tokens']),
      maxOutputTokens: parseInt(raw['max_output_tokens']),
      thinkingMode: aiThinkingModeFromString(raw['thinking_mode'] ?? 'auto'),
      includeThoughts: _parseOptIn(raw['include_thoughts']),
      responsesUsePreviousResponseId:
          _parseBool(raw['responses_use_previous_response_id']),
      responsesRequestReasoningSummary:
          _parseBool(raw['responses_request_reasoning_summary']),
      additional: parseAiJsonObject(raw['extra'] ?? raw['additional']),
    );
  }

  AiEndpointConfig copyWith({
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
    return AiEndpointConfig(
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

  /// Overlay [override] on top of this config.
  ///
  /// Non-empty strings and non-null values from [override] win; headers and
  /// [additional] are merged key-wise. This is how a per-feature model override
  /// is layered on top of a provider's own configuration.
  AiEndpointConfig mergedWith(AiEndpointConfig override) {
    return copyWith(
      model: override.model.isNotEmpty ? override.model : model,
      apiKey: override.apiKey.isNotEmpty ? override.apiKey : apiKey,
      baseUrl: override.baseUrl ?? baseUrl,
      headers: <String, String>{...headers, ...override.headers},
      temperature: override.temperature ?? temperature,
      topP: override.topP ?? topP,
      maxTokens: override.maxTokens ?? maxTokens,
      maxOutputTokens: override.maxOutputTokens ?? maxOutputTokens,
      responsesUsePreviousResponseId: override.responsesUsePreviousResponseId ??
          responsesUsePreviousResponseId,
      responsesRequestReasoningSummary:
          override.responsesRequestReasoningSummary ??
              responsesRequestReasoningSummary,
      additional: mergeAiMaps(additional, override.additional),
    );
  }
}

/// Strip well-known operation suffixes so a full endpoint URL becomes a base.
///
/// Users routinely paste `https://host/v1/chat/completions` where a base URL is
/// expected; clients then append their own path and produce a 404.
String? deriveAiBaseUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return url.trim();
  }

  const removableSegments = {
    'chat',
    'messages',
    'completions',
    'responses',
    'invoke',
    'openai',
  };

  final segments = uri.pathSegments.toList(growable: true);
  while (segments.isNotEmpty &&
      removableSegments.contains(segments.last.toLowerCase())) {
    segments.removeLast();
  }

  final base = uri.replace(pathSegments: segments).toString();
  if (base.endsWith('/')) {
    return base.substring(0, base.length - 1);
  }
  return base;
}

/// Parse custom headers, accepting either JSON or `k=v;k=v`.
Map<String, String> parseAiHeaders(String? headersRaw) {
  if (headersRaw == null || headersRaw.trim().isEmpty) {
    return const {};
  }

  try {
    final decoded = jsonDecode(headersRaw);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    }
  } catch (_) {
    final map = <String, String>{};
    for (final entry in headersRaw.split(';')) {
      final parts = entry.split('=');
      if (parts.length == 2) {
        map[parts[0].trim()] = parts[1].trim();
      }
    }
    if (map.isNotEmpty) {
      return map;
    }
  }

  return const {};
}

/// Decode a JSON object, returning null on anything else.
Map<String, dynamic>? parseAiJsonObject(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {}

  return null;
}

/// Shallow-merge two optional maps, with [override] winning.
Map<String, dynamic>? mergeAiMaps(
  Map<String, dynamic>? base,
  Map<String, dynamic>? override,
) {
  if (base == null && override == null) {
    return null;
  }

  return <String, dynamic>{...?base, ...?override};
}

/// Opt-in flag: false unless explicitly affirmative.
bool _parseOptIn(String? value) {
  final raw = (value ?? 'false').trim().toLowerCase();
  return raw == 'true' || raw == '1' || raw == 'yes';
}

/// Opt-out flag: null when unset, otherwise true unless explicitly negative.
bool? _parseBool(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final raw = value.trim().toLowerCase();
  return !(raw == 'false' || raw == '0' || raw == 'no');
}
