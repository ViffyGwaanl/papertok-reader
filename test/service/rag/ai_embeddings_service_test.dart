import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';

void main() {
  test('local OpenAI-compatible endpoint with /v1 does not duplicate v1 path',
      () {
    expect(
      AiEmbeddingsService.buildLocalEmbeddingUrl('http://localhost:3003/v1'),
      'http://localhost:3003/v1/embeddings',
    );
    expect(
      AiEmbeddingsService.buildLocalEmbeddingUrl(
        'http://localhost:3003/v1/',
      ),
      'http://localhost:3003/v1/embeddings',
    );
  });

  test('local Ollama endpoint keeps api embeddings path', () {
    expect(
      AiEmbeddingsService.buildLocalEmbeddingUrl('http://localhost:11434'),
      'http://localhost:11434/api/embeddings',
    );
  });
}
