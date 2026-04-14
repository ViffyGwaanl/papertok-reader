import 'dart:async';
import 'dart:convert';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_api_key_entry.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/service/ai/api_key_rotation.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:dio/dio.dart';

/// OpenAI-compatible embeddings client that reuses Provider Center configs.
class AiEmbeddingsService {
  AiEmbeddingsService._();

  static final Dio _dio = Dio();

  static const String defaultEmbeddingModel = 'text-embedding-3-large';

  static Future<List<double>> embedQuery(
    String text, {
    String model = defaultEmbeddingModel,
    String? providerId,
    int timeoutSeconds = 60,
  }) async {
    final list = await embedDocuments(
      [text],
      model: model,
      providerId: providerId,
      timeoutSeconds: timeoutSeconds,
    );
    return list.first;
  }

  /// Whether any embedding provider is available (remote or local).
  static bool get isAvailable {
    final localEndpoint = Prefs().localEmbeddingEndpoint;
    if (localEndpoint != null && localEndpoint.trim().isNotEmpty) return true;

    final pid = Prefs().selectedAiService;
    final meta = Prefs().getAiProviderMeta(pid);
    if (meta == null) return false;
    return meta.type == AiProviderType.openaiCompatible ||
        meta.type == AiProviderType.openaiResponses;
  }

  static Future<List<List<double>>> embedDocuments(
    List<String> texts, {
    String model = defaultEmbeddingModel,
    String? providerId,
    int timeoutSeconds = 60,
  }) async {
    if (texts.isEmpty) return const [];

    // Try local embedding endpoint first (Ollama, llama.cpp, etc.).
    final localEndpoint = Prefs().localEmbeddingEndpoint;
    if (localEndpoint != null && localEndpoint.trim().isNotEmpty) {
      return _embedViaLocalEndpoint(
        texts,
        localEndpoint.trim(),
        Prefs().localEmbeddingModel,
        timeoutSeconds,
      );
    }

    final pid = providerId ?? Prefs().selectedAiService;
    final meta = Prefs().getAiProviderMeta(pid);

    // Only OpenAI-compatible providers are supported for remote embedding.
    if (meta != null &&
        meta.type != AiProviderType.openaiCompatible &&
        meta.type != AiProviderType.openaiResponses) {
      throw StateError(
        'Embeddings require an OpenAI-compatible provider or a local '
        'embedding endpoint (current: ${meta.type}). Configure a local '
        'endpoint in Settings → AI → Local Embedding.',
      );
    }

    final registryIdentifier = meta == null
        ? pid
        : switch (meta.type) {
            AiProviderType.openaiResponses => 'openai-responses',
            AiProviderType.openaiCompatible => 'openai',
            AiProviderType.anthropic => 'claude',
            AiProviderType.gemini => 'gemini',
          };

    final savedConfig = Prefs().getAiConfig(pid);
    if (savedConfig.isEmpty) {
      throw StateError('AI provider is not configured for embeddings.');
    }

    final baseConfig = LangchainAiConfig.fromPrefs(
      registryIdentifier,
      savedConfig,
    );
    final baseUrl = baseConfig.baseUrl ?? 'https://api.openai.com/v1';
    final url = _join(baseUrl, 'embeddings');

    // Rotation: use managed `api_keys` list when present; fallback to `api_key`.
    final managedEntries = decodeAiApiKeyEntries(savedConfig);
    final hasManagedList = (savedConfig['api_keys'] ?? '').trim().isNotEmpty;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    int parseInt(String key, int fallback) {
      final v = (savedConfig[key] ?? '').trim();
      if (v.isEmpty) return fallback;
      return int.tryParse(v) ?? fallback;
    }

    final failureThreshold = parseInt(
      'api_key_policy_failure_threshold',
      3,
    ).clamp(1, 10);

    final authCooldownMs = Duration(
      minutes: parseInt(
        'api_key_policy_auth_cooldown_min',
        60,
      ).clamp(1, 24 * 60),
    ).inMilliseconds;
    final rateLimitCooldownMs = Duration(
      minutes: parseInt(
        'api_key_policy_rate_limit_cooldown_min',
        5,
      ).clamp(1, 24 * 60),
    ).inMilliseconds;
    final serviceCooldownMs = Duration(
      minutes: parseInt(
        'api_key_policy_service_cooldown_min',
        1,
      ).clamp(1, 24 * 60),
    ).inMilliseconds;

    bool isCoolingDown(AiApiKeyEntry e) {
      final until = e.disabledUntil;
      return until != null && until > nowMs;
    }

    final eligibleEntries = managedEntries
        .where((e) => e.enabled && e.key.trim().isNotEmpty && !isCoolingDown(e))
        .toList(growable: false);

    final allEnabledEntries = managedEntries
        .where((e) => e.enabled && e.key.trim().isNotEmpty)
        .toList(growable: false);

    final candidates = eligibleEntries.isNotEmpty
        ? eligibleEntries
        : (allEnabledEntries.toList(growable: true)
          ..sort(
            (a, b) => (a.disabledUntil ?? 0).compareTo(b.disabledUntil ?? 0),
          ));

    final startIndex = apiKeyRoundRobin.startIndex(pid);
    final attempts = candidates.isEmpty ? 1 : candidates.length;

    List<AiApiKeyEntry> replaceEntry(
      List<AiApiKeyEntry> list,
      AiApiKeyEntry entry,
    ) {
      final idx = list.indexWhere((e) => e.id == entry.id);
      if (idx < 0) return list;
      final next = [...list];
      next[idx] = entry;
      return next;
    }

    void persistManagedKeys(
      List<AiApiKeyEntry> entries, {
      required String activeKey,
    }) {
      if (!hasManagedList) return;
      final cfg = Prefs().getAiConfig(pid);
      cfg['api_keys'] = encodeAiApiKeyEntries(entries);
      cfg['api_key'] = activeKey;
      Prefs().saveAiConfig(pid, cfg);
    }

    bool shouldRetry(Object error) {
      final message = error.toString().toLowerCase();
      return message.contains('401') ||
          message.contains('unauthorized') ||
          message.contains('invalid api key') ||
          message.contains('429') ||
          message.contains('rate limit') ||
          message.contains('503') ||
          message.contains('bad gateway');
    }

    int cooldownMsFor(Object error) {
      final message = error.toString().toLowerCase();
      if (message.contains('401') ||
          message.contains('unauthorized') ||
          message.contains('invalid api key')) {
        return authCooldownMs;
      }
      if (message.contains('429') || message.contains('rate limit')) {
        return rateLimitCooldownMs;
      }
      return serviceCooldownMs;
    }

    for (var attempt = 0; attempt < attempts; attempt++) {
      final attemptEntry = candidates.isEmpty
          ? null
          : candidates[(startIndex + attempt) % candidates.length];

      final attemptKey = (attemptEntry?.key.trim().isNotEmpty ?? false)
          ? attemptEntry!.key.trim()
          : baseConfig.apiKey;

      if (attemptKey.trim().isEmpty) {
        throw StateError('Missing API key for embeddings provider=$pid.');
      }

      final headers = <String, String>{}..addAll(baseConfig.headers);
      headers.putIfAbsent('Content-Type', () => 'application/json');
      if (!headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer $attemptKey';
      }

      try {
        final res = await _dio
            .post(
              url,
              data: jsonEncode({'model': model, 'input': texts}),
              options: Options(headers: headers),
            )
            .timeout(Duration(seconds: timeoutSeconds.clamp(5, 300)));

        final data = res.data;
        final decoded = data is String ? jsonDecode(data) : data;

        if (decoded is! Map || decoded['data'] is! List) {
          throw StateError('Unexpected embeddings response shape');
        }

        final list = (decoded['data'] as List)
            .map((e) => e is Map ? e['embedding'] : null)
            .whereType<List>()
            .map(
              (e) =>
                  e.map((x) => (x as num).toDouble()).toList(growable: false),
            )
            .toList(growable: false);

        if (list.length != texts.length) {
          throw StateError(
            'Embeddings response size mismatch: expected ${texts.length} got ${list.length}',
          );
        }

        // Success: advance round-robin index and persist stats.
        if (candidates.length > 1) {
          apiKeyRoundRobin.advance(pid, startIndex + attempt + 1);
        }

        if (attemptEntry != null && hasManagedList) {
          final updated = attemptEntry.copyWith(
            lastUsedAt: nowMs,
            lastSuccessAt: nowMs,
            successCount: (attemptEntry.successCount ?? 0) + 1,
            consecutiveFailures: 0,
            disabledUntil: null,
            updatedAt: nowMs,
          );
          final next = replaceEntry(managedEntries, updated);
          persistManagedKeys(next, activeKey: attemptKey);
        }

        return list;
      } catch (e) {
        final mapped = e.toString();
        AnxLog.warning(
          'Embeddings: request failed provider=$pid attempt=${attempt + 1}/$attempts error=$mapped',
        );

        if (attemptEntry != null && hasManagedList) {
          final retryable = shouldRetry(e);
          final nextConsecutive = (attemptEntry.consecutiveFailures ?? 0) + 1;

          int? disabledUntil;
          if (retryable && nextConsecutive >= failureThreshold) {
            disabledUntil = nowMs + cooldownMsFor(e);
          }

          final updated = attemptEntry.copyWith(
            lastUsedAt: nowMs,
            lastFailureAt: nowMs,
            failureCount: (attemptEntry.failureCount ?? 0) + 1,
            consecutiveFailures: nextConsecutive,
            disabledUntil: disabledUntil ?? attemptEntry.disabledUntil,
            updatedAt: nowMs,
          );

          final next = replaceEntry(managedEntries, updated);
          persistManagedKeys(next, activeKey: attemptKey);
        }

        final canRetry = candidates.length > 1 && shouldRetry(e);
        if (canRetry && attempt < attempts - 1) {
          continue;
        }
        rethrow;
      }
    }

    throw StateError('Embeddings failed after $attempts attempt(s).');
  }

  /// Embed texts using a local Ollama-compatible endpoint.
  ///
  /// Supports two API formats:
  /// 1. Ollama: POST /api/embeddings with { model, prompt }
  /// 2. OpenAI-compatible: POST /v1/embeddings with { model, input }
  static Future<List<List<double>>> _embedViaLocalEndpoint(
    List<String> texts,
    String endpoint,
    String model,
    int timeoutSeconds,
  ) async {
    final results = <List<double>>[];
    final isOllama = !endpoint.contains('/v1');
    final url = isOllama
        ? _join(endpoint, 'api/embeddings')
        : _join(endpoint, 'v1/embeddings');

    AnxLog.info('Embeddings: using local endpoint $url model=$model '
        'texts=${texts.length}');

    if (isOllama) {
      // Ollama API: one request per text.
      for (final text in texts) {
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: {'model': model, 'prompt': text},
          options: Options(
            sendTimeout: Duration(seconds: timeoutSeconds),
            receiveTimeout: Duration(seconds: timeoutSeconds),
          ),
        );
        final embedding = response.data?['embedding'];
        if (embedding is List) {
          results.add(embedding.cast<num>().map((n) => n.toDouble()).toList());
        } else {
          throw StateError('Local embedding response missing "embedding" field');
        }
      }
    } else {
      // OpenAI-compatible batch API.
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {'model': model, 'input': texts},
        options: Options(
          sendTimeout: Duration(seconds: timeoutSeconds),
          receiveTimeout: Duration(seconds: timeoutSeconds),
        ),
      );
      final data = response.data?['data'] as List<dynamic>?;
      if (data == null) {
        throw StateError('Local embedding response missing "data" field');
      }
      for (final item in data) {
        final embedding = (item as Map<String, dynamic>)['embedding'] as List;
        results.add(embedding.cast<num>().map((n) => n.toDouble()).toList());
      }
    }

    return results;
  }

  static String _join(String baseUrl, String path) {
    if (baseUrl.endsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
}
