import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final env = Platform.environment;
  final liveEnabled = env['PAPERTOK_LIVE_RAG_SMOKE'] == '1';
  final baseUrl = env['PAPERTOK_LIVE_RAG_BASE_URL']?.trim() ?? '';
  final apiKey = env['PAPERTOK_LIVE_RAG_API_KEY']?.trim() ?? '';
  final embeddingModel =
      env['PAPERTOK_LIVE_EMBED_MODEL']?.trim() ?? 'Qwen/Qwen3-Embedding-8B';
  final rerankModel =
      env['PAPERTOK_LIVE_RERANK_MODEL']?.trim() ?? 'Qwen/Qwen3-Reranker-8B';
  final timeoutSeconds = int.tryParse(
        env['PAPERTOK_LIVE_RAG_TIMEOUT_SECONDS'] ?? '',
      ) ??
      20;

  final missing = <String>[
    if (baseUrl.isEmpty) 'PAPERTOK_LIVE_RAG_BASE_URL',
    if (apiKey.isEmpty) 'PAPERTOK_LIVE_RAG_API_KEY',
    if (embeddingModel.isEmpty) 'PAPERTOK_LIVE_EMBED_MODEL',
    if (rerankModel.isEmpty) 'PAPERTOK_LIVE_RERANK_MODEL',
  ];
  final skipReason = !liveEnabled
      ? 'Set PAPERTOK_LIVE_RAG_SMOKE=1 to run local provider smoke tests.'
      : missing.isNotEmpty
          ? 'Missing ${missing.join(', ')}.'
          : null;

  group('live RAG gateway smoke', skip: skipReason, () {
    test('embedding endpoint returns finite vectors', () async {
      final decoded = await _postJson(
        uri: _endpoint(baseUrl, 'embeddings'),
        apiKey: apiKey,
        timeout: Duration(seconds: timeoutSeconds),
        body: {
          'model': embeddingModel,
          'input': [
            'PaperTok SourceRef keeps RAG evidence traceable.',
            'SourceRef 可以让卡片跳回原文。',
          ],
        },
      );

      final data = decoded['data'];
      expect(data, isA<List>());
      expect(data, hasLength(2));
      for (final item in data as List) {
        expect(item, isA<Map>());
        final embedding = (item as Map)['embedding'];
        expect(embedding, isA<List>());
        expect(embedding, isNotEmpty);
        expect(
          (embedding as List).every(
            (value) => value is num && value.toDouble().isFinite,
          ),
          isTrue,
        );
      }
    });

    test('rerank endpoint returns finite relevance scores', () async {
      final decoded = await _postJson(
        uri: _endpoint(baseUrl, 'rerank'),
        apiKey: apiKey,
        timeout: Duration(seconds: timeoutSeconds),
        body: {
          'model': rerankModel,
          'query': 'Which document talks about SourceRef?',
          'documents': [
            'SourceRef records book anchors and evidence jump links.',
            'The weather is sunny with light wind.',
            'Reranking reorders retrieval candidates by relevance.',
          ],
          'return_documents': false,
          'top_n': 3,
          'instruction': 'Prefer direct evidence about PaperTok source refs.',
        },
      );

      final results = decoded['results'];
      expect(results, isA<List>());
      expect(results, isNotEmpty);
      for (final item in results as List) {
        expect(item, isA<Map>());
        final index = (item as Map)['index'];
        final score = item['relevance_score'] ?? item['score'];
        expect(index, isA<num>());
        expect((index as num).toInt(), inInclusiveRange(0, 2));
        expect(score, isA<num>());
        expect((score as num).toDouble().isFinite, isTrue);
      }
    });
  });
}

Uri _endpoint(String baseUrl, String path) {
  final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return Uri.parse('$normalized/$path');
}

Future<Map<String, dynamic>> _postJson({
  required Uri uri,
  required String apiKey,
  required Map<String, dynamic> body,
  required Duration timeout,
}) async {
  final response = await http
      .post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(timeout);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    fail('Live RAG smoke failed for ${uri.path}: HTTP ${response.statusCode}.');
  }

  final decoded = jsonDecode(response.body);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  fail('Live RAG smoke failed for ${uri.path}: unexpected response shape.');
}
