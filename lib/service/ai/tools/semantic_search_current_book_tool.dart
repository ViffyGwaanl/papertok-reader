import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/rag/semantic_search_current_book.dart';
import 'package:riverpod/riverpod.dart';

import 'base_tool.dart';

class SemanticSearchCurrentBookTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  SemanticSearchCurrentBookTool(this._ref)
      : super(
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

    final service = SemanticSearchCurrentBook();
    final result = await service.search(
      bookId: reading.book!.id,
      query: q,
      maxResults: maxResults,
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
