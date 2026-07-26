import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/service/rag/ai_library_reranker_factory.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('returns null when library rerank is disabled', () {
    expect(AiLibraryRerankerFactory.buildFromPrefs(), isNull);
  });

  test('builds SiliconFlow-compatible reranker from provider center config',
      () async {
    Prefs().aiProvidersV1 = [
      AiProviderMeta(
        id: 'local-rag',
        name: 'Local RAG',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: 0,
        updatedAt: 0,
      ),
    ];
    Prefs().aiLibraryIndexRerankEnabled = true;
    Prefs().aiLibraryIndexRerankFollowIndexProvider = false;
    Prefs().aiLibraryIndexRerankProviderId = 'local-rag';
    Prefs().aiLibraryIndexRerankModel = 'Qwen/Qwen3-Reranker-8B';
    Prefs().aiLibraryIndexRerankInstruction = 'Prefer direct answers.';
    Prefs().saveAiConfig('local-rag', {
      'url': 'http://localhost:3003/v1/responses',
      'api_key': 'test-key',
      'model': 'gpt-5.5',
    });

    Uri? seenUri;
    Map<String, String>? seenHeaders;
    Map<String, dynamic>? seenBody;

    final rerank = AiLibraryRerankerFactory.buildFromPrefs(
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
            {'index': 0, 'relevance_score': 0.77},
          ],
        };
      },
    );

    expect(rerank, isNotNull);
    final scores = await rerank!(
      'RAG',
      const [
        AiSemanticSearchLibraryRerankCandidate(
          chunkId: 1,
          bookId: 1,
          href: 'a.xhtml',
          anchor: 'A',
          text: 'RAG reranking.',
          score: 0.2,
        ),
      ],
    );

    expect(scores, [0.77]);
    expect(seenUri.toString(), 'http://localhost:3003/v1/rerank');
    expect(seenHeaders?['Authorization'], 'Bearer test-key');
    expect(seenBody?['model'], 'Qwen/Qwen3-Reranker-8B');
    expect(seenBody?['instruction'], 'Prefer direct answers.');
  });
}
