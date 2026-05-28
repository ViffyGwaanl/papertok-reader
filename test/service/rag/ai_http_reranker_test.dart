import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_http_reranker.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

void main() {
  List<AiSemanticSearchLibraryRerankCandidate> candidates() => const [
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 10,
          bookId: 1,
          href: 'chapter-1.xhtml',
          anchor: 'Neural Search',
          text: 'Dense retrieval maps query and passages into vectors.',
          score: 0.31,
        ),
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 11,
          bookId: 1,
          href: 'chapter-2.xhtml',
          anchor: 'Keyword Search',
          text: 'BM25 scores exact lexical matches in an inverted index.',
          score: 0.42,
        ),
      ];

  test('posts SiliconFlow-compatible payload and maps scores by index',
      () async {
    Uri? seenUri;
    Map<String, String>? seenHeaders;
    Map<String, dynamic>? seenBody;

    final reranker = AiHttpReranker(
      baseUrl: 'http://localhost:3003/v1/',
      apiKey: 'test-key',
      model: 'Qwen/Qwen3-Reranker-8B',
      instruction: 'Prioritize passages that directly answer the query.',
      postJson: ({
        required uri,
        required headers,
        required body,
        required timeout,
      }) async {
        seenUri = uri;
        seenHeaders = headers;
        seenBody = body;
        return {
          'results': [
            {'index': 1, 'relevance_score': 0.91},
            {'index': 0, 'relevance_score': 0.22},
          ],
        };
      },
    );

    final scores = await reranker.rerank('BM25 vs vector', candidates());

    expect(scores, [0.22, 0.91]);
    expect(seenUri.toString(), 'http://localhost:3003/v1/rerank');
    expect(seenHeaders?['Authorization'], 'Bearer test-key');
    expect(seenHeaders?['Content-Type'], 'application/json');
    expect(seenBody?['model'], 'Qwen/Qwen3-Reranker-8B');
    expect(seenBody?['query'], 'BM25 vs vector');
    expect(seenBody?['documents'], hasLength(2));
    expect(seenBody?['return_documents'], isFalse);
    expect(seenBody?['top_n'], 2);
    expect(
      seenBody?['instruction'],
      'Prioritize passages that directly answer the query.',
    );
  });

  test('falls back to existing scores when rerank response is malformed',
      () async {
    final reranker = AiHttpReranker(
      baseUrl: 'http://localhost:3003/v1',
      apiKey: 'test-key',
      postJson: ({
        required uri,
        required headers,
        required body,
        required timeout,
      }) async {
        return {'unexpected': true};
      },
    );

    final scores = await reranker.rerank('BM25 vs vector', candidates());

    expect(scores, [0.31, 0.42]);
  });
}
