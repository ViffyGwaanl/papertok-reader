import 'dart:async';

import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';

import 'base_tool.dart';

class _BookshelfLookupInput {
  _BookshelfLookupInput({
    required this.query,
    this.groupId,
    this.includeDeleted = false,
    this.limit,
  });

  final String? query;
  final int? groupId;
  final bool includeDeleted;
  final int? limit;

  factory _BookshelfLookupInput.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value == null) return false;
      final normalized = value.toString().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    return _BookshelfLookupInput(
      query: json['query']?.toString(),
      groupId: parseInt(json['group_id'] ?? json['groupId']),
      includeDeleted: parseBool(json['include_deleted'] ?? json['includeDeleted']),
      limit: parseInt(json['limit']),
    );
  }

  int resolvedLimit([int fallback = 10]) {
    final value = limit ?? fallback;
    return value.clamp(1, 50);
  }
}

class BookshelfLookupTool
    extends RepositoryTool<_BookshelfLookupInput, Map<String, dynamic>> {
  BookshelfLookupTool(this._repository)
      : super(
          name: 'bookshelf_lookup',
          description:
              'Search books on the local shelf by title or author. Optional filters: group_id, include_deleted, limit. Returns a list of matching books, and the meta information(title, author, progress, last reading time) of each book.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Keyword for title or author search. Optional when filtering by group only.',
              },
              'group_id': {
                'type': 'integer',
                'description': 'Optional group identifier to filter books.',
              },
              'include_deleted': {
                'type': 'boolean',
                'description': 'Whether to include deleted books (default false).',
              },
              'limit': {
                'type': 'integer',
                'description': 'Maximum number of results (1-50).',
              },
            },
          },
          timeout: const Duration(seconds: 3),
        );

  final BooksRepository _repository;

  @override
  _BookshelfLookupInput parseInput(Map<String, dynamic> json) {
    return _BookshelfLookupInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(_BookshelfLookupInput input) async {
    final results = await _repository.searchBooks(
      keyword: input.query,
      groupId: input.groupId,
      includeDeleted: input.includeDeleted,
      limit: input.resolvedLimit(),
    );

    return {
      'query': input.query,
      'groupId': input.groupId,
      'includeDeleted': input.includeDeleted,
      'results': results.map((entry) => entry.toMap()).toList(),
    };
  }

  @override
  bool shouldLogError(Object error) {
    return error is! TimeoutException;
  }
}
