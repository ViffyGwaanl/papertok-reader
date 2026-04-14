import 'dart:async';

import 'package:papertok_reader/dao/book_note.dart';
import 'package:papertok_reader/enums/ai_tool_risk_level.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/annotation_ledger.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/ai/tools/input/create_note_input.dart';

import 'base_tool.dart';

/// AI tool to create a note (bookmark-type annotation) in the current book.
///
/// Unlike highlights which mark existing text, notes are user-authored content
/// attached to a position in the book. The AI can use this to save insights,
/// summaries, or analysis results directly into the book's annotation system.
class CreateNoteTool
    extends RepositoryTool<CreateNoteInput, Map<String, dynamic>> {
  CreateNoteTool(this._ref, {this.ledger})
      : super(
          name: 'create_note',
          description:
              'Create a note annotation at a specific position in the current book. '
              'Use this to save insights, summaries, or analysis for the user. '
              'Requires content text and CFI position.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description':
                    'The note content. Supports Markdown formatting.',
              },
              'cfi': {
                'type': 'string',
                'description':
                    'EPUB CFI position where this note should be anchored. '
                    'Use resolve_cfi tool to find the position.',
              },
              'chapter': {
                'type': 'string',
                'description':
                    'Optional chapter title override. If not provided, '
                    'uses the current chapter.',
              },
              'color': {
                'type': 'string',
                'description':
                    'Optional hex color code without # (default: 66CCFF).',
              },
            },
            'required': ['content', 'cfi'],
          },
        );

  final dynamic _ref;
  final AnnotationLedger? ledger;

  @override
  CreateNoteInput parseInput(Map<String, dynamic> json) =>
      CreateNoteInput.fromJson(json);

  @override
  FutureOr<Map<String, dynamic>> run(CreateNoteInput input) async {
    final readingState = _ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No book is currently open');
    }

    final bookId = readingState.book?.id;
    if (bookId == null) {
      throw StateError('Current book has no ID');
    }

    final chapterTitle =
        input.chapter ?? readingState.chapterTitle ?? 'Unknown chapter';
    final color = input.color?.replaceAll('#', '') ?? '66CCFF';

    final bookNote = BookNote(
      bookId: bookId,
      content: '',
      cfi: input.cfi,
      chapter: chapterTitle,
      type: 'bookmark',
      color: color,
      readerNote: input.content,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );

    final noteId = await BookNoteDao().save(bookNote);

    final titleSnippet = input.content.length > 60
        ? input.content.substring(0, 60)
        : input.content;
    ledger?.addNote(
      title: titleSnippet,
      content: input.content,
      chapterTitle: chapterTitle,
    );

    return {
      'id': noteId,
      'content': input.content,
      'chapter': chapterTitle,
    };
  }
}

final AiToolDefinition createNoteToolDefinition = AiToolDefinition(
  id: 'create_note',
  displayNameBuilder: (L10n l10n) => 'Create Note',
  descriptionBuilder: (L10n l10n) =>
      'Create a note annotation in the current book',
  build: (context) => CreateNoteTool(context.ref, ledger: context.annotationLedger).tool,
  riskLevel: AiToolRiskLevel.write,
  scenes: const {AiToolScene.reading},
  isConcurrencySafe: false,
);
