import 'dart:async';

import 'package:langchain_core/tools.dart';

import 'base_tool.dart';
import 'input/book_content_search_input.dart';
import 'repository/book_content_search_repository.dart';

class BookContentSearchTool
    extends RepositoryTool<BookContentSearchInput, Map<String, dynamic>> {
  BookContentSearchTool(
    this._repository,
  ) : super(
          name: 'book_content_search',
          description:
              'Search for keyword matches within a book by bookId and keyword. Optionally control maxResults, maxSnippets, and maxCharacters.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'bookId': {
                'type': 'integer',
                'description': 'Numeric identifier of the target book.',
              },
              'keyword': {
                'type': 'string',
                'description':
                    'Keyword or phrase to search within the book content.',
              },
              'maxResults': {
                'type': 'integer',
                'description':
                    'Maximum number of chapter-level results to return (1-10).',
              },
              'maxSnippets': {
                'type': 'integer',
                'description':
                    'Maximum number of snippets per chapter result (1-10).',
              },
              'maxCharacters': {
                'type': 'integer',
                'description':
                    'Optional limit for snippet length in characters (100-2000).',
              },
            },
            'required': ['bookId', 'keyword'],
          },
          timeout: const Duration(seconds: 20),
        );

  final BookContentSearchRepository _repository;

  @override
  BookContentSearchInput parseInput(Map<String, dynamic> json) {
    return BookContentSearchInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(BookContentSearchInput input) async {
    return _repository.search(input);
  }
}

Tool bookContentSearchTool(BookContentSearchRepository repository) {
  return BookContentSearchTool(repository).tool;
}
