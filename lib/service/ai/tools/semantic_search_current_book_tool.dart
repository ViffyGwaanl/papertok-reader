import 'dart:async';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'base_tool.dart';

typedef SemanticSearchCurrentBookRunner = Future<AiSemanticSearchResult>
    Function({
  required int bookId,
  required String query,
  required int maxResults,
  AiCurrentBookSearchCancellationToken? cancelToken,
});

class SemanticSearchCurrentBookTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  SemanticSearchCurrentBookTool(
    this._ref, {
    SemanticSearchCurrentBookRunner? search,
    Duration searchTimeout = const Duration(seconds: 24),
  })  : _search = search,
        _searchTimeout = searchTimeout,
        super(
          name: 'semantic_search_current_book',
          description:
              'Semantic vector search inside the book the user is currently reading. Requires a pre-built local semantic index (Reading → Settings → Other → AI Semantic Index). Returns evidence snippets with internal jump links.',
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
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 25),
        );

  final Ref _ref;
  final SemanticSearchCurrentBookRunner? _search;
  final Duration _searchTimeout;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final reading = _ref.read(currentReadingProvider);
    if (!reading.isReading || reading.book == null) {
      return {
        'ok': false,
        'message': 'No active reading session detected.',
        'evidence': <Map<String, dynamic>>[],
      };
    }

    final q = (input['query'] ?? '').toString();
    final maxResultsRaw = input['maxResults'];
    final maxResults = (maxResultsRaw is num && maxResultsRaw.isFinite)
        ? maxResultsRaw.toInt().clamp(1, 10)
        : 6;

    final cancelToken = AiCurrentBookSearchCancellationToken();
    final runner = _search ??
        ({
          required int bookId,
          required String query,
          required int maxResults,
          AiCurrentBookSearchCancellationToken? cancelToken,
        }) {
          final service = SemanticSearchCurrentBook(
            maxFallbackVectorRows:
                SemanticSearchCurrentBook.toolFallbackVectorRowBudget,
          );
          return service.search(
            bookId: bookId,
            query: query,
            maxResults: maxResults,
            cancelToken: cancelToken,
          );
        };
    final result = await runner(
      bookId: reading.book!.id,
      query: q,
      maxResults: maxResults,
      cancelToken: cancelToken,
    ).timeout(
      _searchTimeout,
      onTimeout: () {
        cancelToken.cancel();
        return AiSemanticSearchResult(
          ok: false,
          bookId: reading.book!.id,
          query: q,
          evidence: const [],
          cancelled: true,
          message: 'Semantic search cancelled after timeout.',
        );
      },
    );

    return result.toJson();
  }
}

final AiToolDefinition semanticSearchCurrentBookToolDefinition =
    AiToolDefinition(
  id: 'semantic_search_current_book',
  displayNameBuilder: (L10n l10n) => l10n.aiToolSemanticSearchCurrentBookName,
  descriptionBuilder: (L10n l10n) =>
      l10n.aiToolSemanticSearchCurrentBookDescription,
  build: (context) => SemanticSearchCurrentBookTool(context.ref).tool,
);
