import 'dart:async';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_library_reranker_factory.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

import 'base_tool.dart';

class SemanticSearchLibraryTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  SemanticSearchLibraryTool({
    required AiLibraryBookTitleResolver resolveBookTitles,
    SemanticSearchLibrary? service,
    AiIndexDatabase? database,
    AiEmbedQueryFn? embedQuery,
    AiLibraryRerankFn? rerank,
  })  : _service = service ??
            SemanticSearchLibrary(
              database: database,
              resolveBookTitles: resolveBookTitles,
              embedQuery: embedQuery,
              rerank: rerank ?? AiLibraryRerankerFactory.buildFromPrefs(),
            ),
        super(
          name: 'semantic_search_library',
          description:
              'Hybrid semantic search across the whole library. Uses full-text search (FTS/BM25) when available + vector embeddings + MMR deduplication. Returns evidence snippets with internal jump links.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Required. Natural language query.',
              },
              'maxResults': {
                'type': 'integer',
                'description':
                    'Optional. Number of evidence items to return (1-10). Default 6.',
              },
              'onlyIndexed': {
                'type': 'boolean',
                'description':
                    'Optional. If true, only search books that have a succeeded AI index. Default true.',
              },
              'queryVariants': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Optional. Alternate query phrasings or synonyms to fuse with the original query.',
              },
              'neighborWindow': {
                'type': 'integer',
                'description':
                    'Optional. Number of adjacent chunks to merge around each hit (0-3). Default 1.',
              },
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 25),
        );

  final SemanticSearchLibrary _service;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final q = (input['query'] ?? '').toString();

    final maxResultsRaw = input['maxResults'];
    final maxResults = (maxResultsRaw is num && maxResultsRaw.isFinite)
        ? maxResultsRaw.toInt().clamp(1, 10)
        : 6;

    final onlyIndexedRaw = input['onlyIndexed'];
    final onlyIndexed = onlyIndexedRaw is bool ? onlyIndexedRaw : true;

    final queryVariantsRaw = input['queryVariants'];
    final queryVariants = queryVariantsRaw is List
        ? queryVariantsRaw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : null;

    final neighborWindowRaw = input['neighborWindow'];
    final neighborWindow =
        (neighborWindowRaw is num && neighborWindowRaw.isFinite)
            ? neighborWindowRaw.toInt().clamp(0, 3)
            : 1;

    final result = await _service.search(
      query: q,
      maxResults: maxResults,
      onlyIndexed: onlyIndexed,
      queryVariants: queryVariants,
      neighborWindow: neighborWindow,
    );

    return result.toJson();
  }
}

final AiToolDefinition semanticSearchLibraryToolDefinition = AiToolDefinition(
  id: 'semantic_search_library',
  displayNameBuilder: (L10n l10n) => l10n.aiToolSemanticSearchLibraryName,
  descriptionBuilder: (L10n l10n) =>
      l10n.aiToolSemanticSearchLibraryDescription,
  build: (context) {
    Future<Map<int, String>> resolver(Iterable<int> ids) async {
      final books = await context.booksRepository.fetchByIds(ids);
      return {
        for (final e in books.entries) e.key: (e.value.title),
      };
    }

    return SemanticSearchLibraryTool(resolveBookTitles: resolver).tool;
  },
);
