import 'dart:async';

import 'package:anx_reader/service/ai/repository/notes_repository.dart';

import 'base_tool.dart';

class _NotesSearchInput {
  _NotesSearchInput({
    required this.query,
    this.bookId,
    this.from,
    this.to,
    this.limit,
  });

  final String query;
  final int? bookId;
  final DateTime? from;
  final DateTime? to;
  final int? limit;

  factory _NotesSearchInput.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    return _NotesSearchInput(
      query: json['query']?.toString() ?? '',
      bookId: parseInt(json['book_id'] ?? json['bookId']),
      from: parseDate(json['from']?.toString()),
      to: parseDate(json['to']?.toString()),
      limit: parseInt(json['limit']),
    );
  }

  int resolvedLimit([int fallback = 10]) {
    final value = limit ?? fallback;
    return value.clamp(1, 50);
  }
}

class NotesSearchTool
    extends RepositoryTool<_NotesSearchInput, Map<String, dynamic>> {
  NotesSearchTool(this._repository)
      : super(
          name: 'notes_search',
          description:
              'Search user notes by keyword. Optional filters: book_id, from, to (ISO8601), limit.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Keyword of the note content or chapter.',
              },
              'book_id': {
                'type': 'integer',
                'description': 'Optional book identifier to scope the search.',
              },
              'from': {
                'type': 'string',
                'description': 'ISO8601 timestamp to filter notes updated after this time.',
              },
              'to': {
                'type': 'string',
                'description': 'ISO8601 timestamp to filter notes updated before this time.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Maximum number of results (1-50).',
              },
            },
            'required': [],
          },
          timeout: const Duration(seconds: 4),
        );

  final NotesRepository _repository;

  @override
  _NotesSearchInput parseInput(Map<String, dynamic> json) {
    return _NotesSearchInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(_NotesSearchInput input) async {
    final results = await _repository.searchNotes(
      keyword: input.query,
      bookId: input.bookId,
      from: input.from,
      to: input.to,
      limit: input.resolvedLimit(),
    );

    return {
      'query': input.query,
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
