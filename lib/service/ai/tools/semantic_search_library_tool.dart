import 'dart:async';

import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/rag/semantic_search_library.dart';

import 'base_tool.dart';

class SemanticSearchLibraryTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  SemanticSearchLibraryTool({
    required AiLibraryBookTitleResolver resolveBookTitles,
    SemanticSearchLibrary? service,
  })  : _service = service ??
            SemanticSearchLibrary(resolveBookTitles: resolveBookTitles),
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

    final result = await _service.search(
      query: q,
      maxResults: maxResults,
      onlyIndexed: onlyIndexed,
    );

    return result.toJson();
  }
}

final AiToolDefinition semanticSearchLibraryToolDefinition = AiToolDefinition(
  id: 'semantic_search_library',
  displayNameBuilder: (_) => 'Semantic search (library)',
  descriptionBuilder: (_) =>
      'Hybrid semantic search across your library. Requires building AI indexes for books you want to search.',
  build: (context) {
    final resolver = (Iterable<int> ids) async {
      final books = await context.booksRepository.fetchByIds(ids);
      return {
        for (final e in books.entries) e.key: (e.value.title),
      };
    };

    return SemanticSearchLibraryTool(resolveBookTitles: resolver).tool;
  },
);
