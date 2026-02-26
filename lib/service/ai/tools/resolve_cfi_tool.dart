import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:riverpod/riverpod.dart';

import 'base_tool.dart';
import 'repository/chapter_content_repository.dart';

/// Resolve an EPUB CFI into chapter metadata (TOC label/href) without navigating.
class ResolveCfiTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ResolveCfiTool(
    this._ref,
    this._repository,
  ) : super(
          name: 'resolve_cfi',
          description:
              'Resolve an EPUB CFI string into best-effort chapter metadata (TOC title/href). Use this to turn a search result CFI into a human-friendly location or to build internal jump links.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'cfi': {
                'type': 'string',
                'description':
                    'Required. EPUB CFI string such as epubcfi(...).',
              },
            },
            'required': ['cfi'],
          },
          timeout: const Duration(seconds: 6),
        );

  final Ref _ref;
  final ChapterContentRepository _repository;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final cfi = (input['cfi'] ?? '').toString().trim();
    if (cfi.isEmpty) {
      throw ArgumentError('cfi must not be empty');
    }

    final resolved = await _repository.resolveCfi(_ref, cfi);

    // Use Paper Reader deep link.
    final reading = _ref.read(currentReadingProvider);
    final bookId = reading.book?.id;

    final jumpLink = (bookId == null)
        ? null
        : PaperReaderReaderIntent(bookId: bookId, cfi: cfi).toUri().toString();

    return {
      ...resolved,
      if (jumpLink != null) 'jumpLink': jumpLink,
      if (jumpLink != null) 'markdownJumpLink': '[Jump]($jumpLink)',
    };
  }
}

final AiToolDefinition resolveCfiToolDefinition = AiToolDefinition(
  id: 'resolve_cfi',
  displayNameBuilder: (L10n l10n) => l10n.aiToolResolveCfiName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolResolveCfiDescription,
  build: (context) =>
      ResolveCfiTool(context.ref, const ChapterContentRepository()).tool,
);
