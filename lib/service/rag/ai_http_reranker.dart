import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

typedef AiRerankJsonPost = Future<Map<String, dynamic>> Function({
  required Uri uri,
  required Map<String, String> headers,
  required Map<String, dynamic> body,
  required Duration timeout,
});

class AiHttpReranker {
  const AiHttpReranker({
    required this.baseUrl,
    required this.apiKey,
    this.model = 'Qwen/Qwen3-Reranker-8B',
    this.instruction,
    this.timeout = const Duration(seconds: 20),
    this.maxCandidates = 40,
    this.maxDocumentChars = 1800,
    this.postJson = defaultPostJson,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String? instruction;
  final Duration timeout;
  final int maxCandidates;
  final int maxDocumentChars;
  final AiRerankJsonPost postJson;

  Future<List<double>> rerank(
    String query,
    List<AiSemanticSearchLibraryRerankCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return const [];

    final fallback = candidates.map((c) => c.score).toList(growable: false);
    final key = apiKey.trim();

    final limit = maxCandidates.clamp(1, candidates.length);
    final visible = candidates.take(limit).toList(growable: false);
    final documents = visible
        .map((c) => _documentText(c, maxDocumentChars))
        .toList(growable: false);

    try {
      final decoded = await postJson(
        uri: _endpointUri(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
        body: {
          'model': model,
          'query': query,
          'documents': documents,
          'return_documents': false,
          'top_n': documents.length,
          if ((instruction ?? '').trim().isNotEmpty)
            'instruction': instruction!.trim(),
        },
        timeout: timeout,
      );

      final results = decoded['results'];
      if (results is! List) return fallback;

      final next = List<double>.from(fallback);
      var accepted = 0;
      for (final item in results) {
        if (item is! Map) continue;
        final rawIndex = item['index'];
        final rawScore = item['relevance_score'] ?? item['score'];
        if (rawIndex is! num || rawScore is! num) continue;
        final index = rawIndex.toInt();
        if (index < 0 || index >= visible.length) continue;
        next[index] = rawScore.toDouble().clamp(0.0, 1.0).toDouble();
        accepted++;
      }

      return accepted == 0 ? fallback : next;
    } catch (_) {
      return fallback;
    }
  }

  static Uri _endpointUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return Uri.parse('$normalized/rerank');
  }

  static String _documentText(
    AiSemanticSearchLibraryRerankCandidate candidate,
    int maxChars,
  ) {
    final buffer = StringBuffer();
    final anchor = candidate.anchor.trim();
    if (anchor.isNotEmpty) {
      buffer
        ..writeln(anchor)
        ..writeln();
    }
    buffer.write(candidate.text.replaceAll(RegExp(r'\s+'), ' ').trim());

    final text = buffer.toString().trim();
    final limit = math.max(128, maxChars);
    if (text.length <= limit) return text;
    return '${text.substring(0, limit).trim()}...';
  }

  static Future<Map<String, dynamic>> defaultPostJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Rerank request failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('Unexpected rerank response shape');
  }
}
