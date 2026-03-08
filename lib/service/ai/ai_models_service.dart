import 'dart:convert';

import 'package:anx_reader/models/ai_model_capability.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:dio/dio.dart';

class AiModelsService {
  static final Dio _dio = Dio();

  static String registryIdentifierFor(AiProviderMeta provider) {
    switch (provider.type) {
      case AiProviderType.anthropic:
        return 'claude';
      case AiProviderType.gemini:
        return 'gemini';
      case AiProviderType.openaiResponses:
        return 'openai-responses';
      case AiProviderType.openaiCompatible:
        return 'openai';
    }
  }

  /// Fetch structured model capabilities for the provider.
  ///
  /// Note: OpenAI-compatible gateways often expose only model ids. In that
  /// case we still return capabilities with id-only metadata so the UI and
  /// caches remain consistent.
  static Future<List<AiModelCapability>> fetchModelCapabilities({
    required AiProviderMeta provider,
    required Map<String, String> rawConfig,
  }) async {
    final registryId = registryIdentifierFor(provider);
    final config = LangchainAiConfig.fromPrefs(registryId, rawConfig);

    switch (provider.type) {
      case AiProviderType.openaiCompatible:
      case AiProviderType.openaiResponses:
        return _fetchOpenAICompatible(config);
      case AiProviderType.anthropic:
        return _fetchAnthropic(config);
      case AiProviderType.gemini:
        return _fetchGemini(config);
    }
  }

  /// Backward-compatible helper for places that only need model ids.
  static Future<List<String>> fetchModels({
    required AiProviderMeta provider,
    required Map<String, String> rawConfig,
  }) async {
    final models = await fetchModelCapabilities(
      provider: provider,
      rawConfig: rawConfig,
    );
    return models.map((e) => e.id).toList(growable: false);
  }

  static Future<List<AiModelCapability>> _fetchOpenAICompatible(
    LangchainAiConfig config,
  ) async {
    final baseUrl = config.baseUrl ?? 'https://api.openai.com/v1';
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);
    if (config.apiKey.isNotEmpty && !headers.containsKey('Authorization')) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    final res = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map && decoded['data'] is List) {
      final list = decoded['data'] as List;
      final models = <String, AiModelCapability>{};
      for (final item in list) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        models[id] = AiModelCapability(id: id);
      }
      final result = models.values.toList(growable: false)
        ..sort((a, b) => a.id.compareTo(b.id));
      return result;
    }

    return const [];
  }

  static Future<List<AiModelCapability>> _fetchAnthropic(
    LangchainAiConfig config,
  ) async {
    final baseUrl = config.baseUrl ?? 'https://api.anthropic.com/v1';
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);

    if (config.apiKey.isNotEmpty && !headers.containsKey('x-api-key')) {
      headers['x-api-key'] = config.apiKey;
    }
    headers.putIfAbsent('anthropic-version', () => '2023-06-01');

    final res = await _dio.get(
      url,
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map && decoded['data'] is List) {
      final list = decoded['data'] as List;
      final models = <String, AiModelCapability>{};
      for (final item in list) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final displayName = (item['display_name'] ?? '').toString().trim();
        final supportsThinking = displayName.contains('3.7') ||
            id.contains('3-7') ||
            id.contains('thinking');
        models[id] = AiModelCapability(
          id: id,
          supportsThinking: supportsThinking,
        );
      }
      final result = models.values.toList(growable: false)
        ..sort((a, b) => a.id.compareTo(b.id));
      return result;
    }

    return const [];
  }

  static Future<List<AiModelCapability>> _fetchGemini(
    LangchainAiConfig config,
  ) async {
    final rawBase =
        config.baseUrl ?? 'https://generativelanguage.googleapis.com';

    final baseUri = Uri.tryParse(rawBase);
    final hasV1Beta =
        baseUri != null && baseUri.pathSegments.contains('v1beta');
    final baseUrl = hasV1Beta ? rawBase : _join(rawBase, 'v1beta');
    final url = _join(baseUrl, 'models');

    final headers = <String, String>{}..addAll(config.headers);
    if (config.apiKey.isNotEmpty && !headers.containsKey('x-goog-api-key')) {
      headers['x-goog-api-key'] = config.apiKey;
    }

    final uri = Uri.parse(url).replace(
      queryParameters: {
        ...Uri.parse(url).queryParameters,
        if (config.apiKey.isNotEmpty) 'key': config.apiKey,
      },
    );

    final res = await _dio.get(
      uri.toString(),
      options: Options(headers: headers),
    );

    final data = res.data;
    final decoded = data is String ? jsonDecode(data) : data;

    if (decoded is Map && decoded['models'] is List) {
      final list = decoded['models'] as List;
      final models = <String, AiModelCapability>{};
      for (final item in list) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final id = name.startsWith('models/')
            ? name.substring('models/'.length)
            : name;
        if (id.isEmpty) continue;
        final methods = (item['supportedGenerationMethods'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const <String>[];
        final supportsTools = methods.any(
          (m) => m.contains('generateContent') || m.contains('streamGenerate'),
        );
        final supportsThinking = id.contains('2.5') || id.contains('thinking');
        models[id] = AiModelCapability(
          id: id,
          contextWindow: (item['inputTokenLimit'] as num?)?.toInt(),
          maxOutputTokens: (item['outputTokenLimit'] as num?)?.toInt(),
          supportsTools: supportsTools,
          supportsImages: true,
          supportsThinking: supportsThinking,
        );
      }
      final result = models.values.toList(growable: false)
        ..sort((a, b) => a.id.compareTo(b.id));
      return result;
    }

    return const [];
  }

  static String _join(String baseUrl, String path) {
    if (baseUrl.endsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
}
