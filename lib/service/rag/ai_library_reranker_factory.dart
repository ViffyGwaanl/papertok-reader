import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/ai_structured_generation_service.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/rag/ai_http_reranker.dart';
import 'package:papertok_reader/service/rag/ai_llm_reranker.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

class AiLibraryRerankerFactory {
  const AiLibraryRerankerFactory._();

  static AiLibraryRerankFn? buildFromPrefs({
    AiRerankJsonPost? postJson,
    AiStructuredGenerationService? structuredGeneration,
  }) {
    final prefs = Prefs();
    if (!prefs.aiLibraryIndexRerankEnabled) return null;

    final mode = prefs.aiLibraryIndexRerankMode;
    final providerId = prefs.aiLibraryIndexRerankProviderIdEffective.trim();

    if (mode == 'llm') {
      return AiLlmReranker(
        structuredGeneration:
            structuredGeneration ?? const AiStructuredGenerationService(),
        providerId: providerId.isEmpty ? null : providerId,
        timeout: Duration(seconds: prefs.aiLibraryIndexRerankTimeoutSeconds),
        maxCandidates: prefs.aiLibraryIndexRerankMaxCandidates,
      ).rerank;
    }

    if (providerId.isEmpty) return null;
    final meta = prefs.getAiProviderMeta(providerId);
    final rawConfig = prefs.getAiConfig(providerId);
    if (rawConfig.isEmpty) return null;

    final registryId = LangchainAiConfig.registryIdentifierForProvider(meta);
    final config = LangchainAiConfig.fromPrefs(registryId, rawConfig);
    final baseUrl = config.baseUrl;
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;

    return AiHttpReranker(
      baseUrl: baseUrl,
      apiKey: config.apiKey,
      model: prefs.aiLibraryIndexRerankModelEffective,
      instruction: prefs.aiLibraryIndexRerankInstruction,
      timeout: Duration(seconds: prefs.aiLibraryIndexRerankTimeoutSeconds),
      maxCandidates: prefs.aiLibraryIndexRerankMaxCandidates,
      maxDocumentChars: prefs.aiLibraryIndexRerankMaxDocumentChars,
      postJson: postJson ?? AiHttpReranker.defaultPostJson,
    ).rerank;
  }
}
