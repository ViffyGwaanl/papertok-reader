import 'package:papertok_reader/service/ai/ai_structured_generation_service.dart';
import 'package:papertok_reader/service/rag/ai_llm_reranker.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM reranker parses structured scores in candidate order', () async {
    final reranker = AiLlmReranker(
      structuredGeneration: AiStructuredGenerationService(
        generateText: ({
          required systemPrompt,
          required userPrompt,
          providerId,
          config,
          timeout = const Duration(seconds: 30),
        }) async {
          expect(systemPrompt, contains('reranker'));
          expect(userPrompt, contains('Candidate 2'));
          return '{"scores":[0.1,0.9]}';
        },
      ),
    );

    final scores = await reranker.rerank(
      'needle',
      const [
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 1,
          bookId: 1,
          href: 'a.xhtml',
          anchor: 'A',
          text: 'less relevant',
          score: 0.8,
        ),
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 2,
          bookId: 1,
          href: 'b.xhtml',
          anchor: 'B',
          text: 'more relevant',
          score: 0.2,
        ),
      ],
    );

    expect(scores, [0.1, 0.9]);
  });

  test('LLM reranker falls back to existing scores on malformed output',
      () async {
    final reranker = AiLlmReranker(
      structuredGeneration: AiStructuredGenerationService(
        generateText: ({
          required systemPrompt,
          required userPrompt,
          providerId,
          config,
          timeout = const Duration(seconds: 30),
        }) async {
          return '{"scores":[1]}';
        },
      ),
    );

    final scores = await reranker.rerank(
      'needle',
      const [
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 1,
          bookId: 1,
          href: 'a.xhtml',
          anchor: 'A',
          text: 'first',
          score: 0.7,
        ),
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 2,
          bookId: 1,
          href: 'b.xhtml',
          anchor: 'B',
          text: 'second',
          score: 0.3,
        ),
      ],
    );

    expect(scores, [0.7, 0.3]);
  });
}
