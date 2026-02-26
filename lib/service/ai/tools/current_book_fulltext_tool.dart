import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/text/word_count.dart';
import 'package:riverpod/riverpod.dart';

import 'base_tool.dart';
import 'repository/chapter_content_repository.dart';

/// Returns full-book plain text when the current book is small enough.
///
/// This is a Phase-1 RAG helper: for short books, it is often better to use the
/// entire text as context instead of doing retrieval.
class CurrentBookFulltextTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CurrentBookFulltextTool(
    this._ref,
    this._repository,
  ) : super(
          name: 'current_book_fulltext',
          description:
              'Retrieve the full plain-text content of the currently opened book, but only when it is short enough. Use this as an "auto full-context" mode for short books. If the book is too long, the tool will refuse and you should use search + chapter tools instead.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'shortBookMaxCharacters': {
                'type': 'integer',
                'description':
                    'Optional. Max characters to qualify as a short book. Defaults to 50000.',
              },
              'includeHeadings': {
                'type': 'boolean',
                'description':
                    'Optional. Include Markdown headings between sections (best-effort). Defaults to false.',
              },
            },
          },
          timeout: const Duration(seconds: 12),
        );

  final Ref _ref;
  final ChapterContentRepository _repository;

  static const int _defaultShortBookMaxCharacters = 50000;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final rawMax = input['shortBookMaxCharacters'];
    final maxChars = (rawMax is num && rawMax.isFinite)
        ? rawMax.toInt().clamp(10000, 120000)
        : _defaultShortBookMaxCharacters;

    final includeHeadings = input['includeHeadings'] == true;

    // Early-stop at maxChars+1 so we can decide whether the book is "short"
    // without materialising very large payloads.
    final result = await _repository.fetchBookContent(
      _ref,
      stopAtCharacters: maxChars + 1,
      maxCharacters: maxChars + 1,
      includeHeadings: includeHeadings,
    );

    final content =
        (result['content'] is String) ? (result['content'] as String) : '';
    final truncated = result['truncated'] == true || content.length > maxChars;

    if (truncated) {
      return {
        'ok': false,
        'isShortBook': false,
        'shortBookMaxCharacters': maxChars,
        'message':
            'Book is longer than the short-book threshold. Use book_content_search + (current_)chapter_content tools instead.',
        'collectedCharacters': content.length,
      };
    }

    final stats = TextStats.fromText(content);

    return {
      'ok': true,
      'isShortBook': true,
      'shortBookMaxCharacters': maxChars,
      'content': content,
      'stats': {
        'characters': stats.characters,
        'nonWhitespaceCharacters': stats.nonWhitespaceCharacters,
        'estimatedWords': stats.estimatedWords,
      },
      'bridge': {
        'sectionCount': result['sectionCount'],
        'includedSections': result['includedSections'],
      },
    };
  }
}

final AiToolDefinition currentBookFulltextToolDefinition = AiToolDefinition(
  id: 'current_book_fulltext',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCurrentBookFulltextName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCurrentBookFulltextDescription,
  build: (context) =>
      CurrentBookFulltextTool(context.ref, const ChapterContentRepository())
          .tool,
);
