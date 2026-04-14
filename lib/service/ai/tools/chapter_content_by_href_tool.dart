import 'dart:async';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/book_content_cache.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/text/word_count.dart';
import 'package:riverpod/riverpod.dart';

import 'base_tool.dart';
import 'input/chapter_content_by_href_input.dart';
import 'repository/chapter_content_repository.dart';

class ChapterContentByHrefTool
    extends RepositoryTool<ChapterContentByHrefInput, Map<String, dynamic>> {
  ChapterContentByHrefTool(
    this._ref,
    this._repository, {
    this.cache,
  }) : super(
          name: 'chapter_content_by_href',
          description:
              'Retrieve the plain-text body of a specific chapter when you already know its TOC href. Use this to quote or analyse a particular section without changing the current reading position. Returns the chapter text trimmed to the requested length.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'href': {
                'type': 'string',
                'description':
                    'Required. Chapter href string obtained from the table of contents tool.',
              },
              'maxCharacters': {
                'type': 'integer',
                'description':
                    'Optional. Hard cap on the number of characters returned (500-12000). Use lower values to avoid long responses.',
              },
            },
            'required': ['href'],
          },
          timeout: const Duration(seconds: 6),
        );

  final Ref _ref;
  final ChapterContentRepository _repository;
  final BookContentCache? cache;

  @override
  ChapterContentByHrefInput parseInput(Map<String, dynamic> json) {
    return ChapterContentByHrefInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(ChapterContentByHrefInput input) async {
    final content = await _repository.fetchByHref(
      _ref,
      href: input.href,
      maxCharacters: input.maxCharacters,
    );

    // Cache optimization: if content hasn't changed since last fetch,
    // return a short marker instead of the full text to save tokens.
    final bookId =
        _ref.read(currentReadingProvider).book?.id?.toString() ?? '';
    if (cache != null && bookId.isNotEmpty) {
      if (cache!.isUnchanged(bookId, input.href, content)) {
        final stats = TextStats.fromText(content);
        return {
          'content': '[unchanged since last read]',
          'cached': true,
          'href': input.href,
          'stats': {
            'characters': stats.characters,
            'nonWhitespaceCharacters': stats.nonWhitespaceCharacters,
            'estimatedWords': stats.estimatedWords,
          },
        };
      }
      cache!.put(bookId, input.href, content);
    }

    final stats = TextStats.fromText(content);
    return {
      'content': content,
      'stats': {
        'characters': stats.characters,
        'nonWhitespaceCharacters': stats.nonWhitespaceCharacters,
        'estimatedWords': stats.estimatedWords,
      },
    };
  }
}

final AiToolDefinition chapterContentByHrefToolDefinition = AiToolDefinition(
  id: 'chapter_content_by_href',
  displayNameBuilder: (L10n l10n) => l10n.aiToolChapterContentByHrefName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolChapterContentByHrefDescription,
  build: (context) => ChapterContentByHrefTool(
    context.ref,
    const ChapterContentRepository(),
    cache: context.bookContentCache,
  ).tool,
);
