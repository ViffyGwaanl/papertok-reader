import 'dart:async';

import 'package:anx_reader/service/ai/tools/input/notes_search_input.dart';
import 'package:anx_reader/service/ai/tools/repository/notes_repository.dart';

import 'base_tool.dart';

class NotesSearchTool
    extends RepositoryTool<NotesSearchInput, Map<String, dynamic>> {
  NotesSearchTool(this._repository)
      : super(
          name: 'notes_search',
          description:
              'Search user notes by keyword, book_id, from, to (ISO8601), limit.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'keyword': {
                'type': 'string',
                'description': 'Keyword of the note content or chapter.',
              },
              'book_id': {
                'type': 'integer',
                'description': 'Optional book identifier to scope the search.',
              },
              'from': {
                'type': 'string',
                'description':
                    'ISO8601 timestamp to filter notes updated after this time.',
              },
              'to': {
                'type': 'string',
                'description':
                    'ISO8601 timestamp to filter notes updated before this time.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Maximum number of results (1-50).',
              },
            },
            // 'required': const <String>[],
          },
          timeout: const Duration(seconds: 4),
        );

  final NotesRepository _repository;

  @override
  NotesSearchInput parseInput(Map<String, dynamic> json) {
    return NotesSearchInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(NotesSearchInput input) async {
    final results = await _repository.searchNotes(
      keyword: input.keyword,
      bookId: input.bookId,
      from: input.from,
      to: input.to,
      limit: input.resolvedLimit(),
    );

    return {
      'keyword': input.keyword,
      'bookId': input.bookId,
      'from': input.from?.toIso8601String(),
      'to': input.to?.toIso8601String(),
      'results': results.map((entry) => entry.toMap()).toList(),
    };
  }

  @override
  bool shouldLogError(Object error) {
    return error is! TimeoutException;
  }
}
