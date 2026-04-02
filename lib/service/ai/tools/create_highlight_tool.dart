import 'dart:async';

import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/enums/ai_tool_scene.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/annotation_ledger.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/input/create_highlight_input.dart';

import 'base_tool.dart';

/// AI tool to create a highlight annotation in the currently open book.
///
/// Requires:
/// - `text`: the text to highlight
/// - `cfi`: EPUB CFI locator (use `resolve_cfi` tool to obtain this)
///
/// Optional:
/// - `note`: a personal note to attach to the highlight
/// - `color`: hex color code (default: FFD700 / gold)
class CreateHighlightTool
    extends RepositoryTool<CreateHighlightInput, Map<String, dynamic>> {
  CreateHighlightTool(this._ref, {this.ledger})
      : super(
          name: 'create_highlight',
          description:
              'Create a highlight annotation in the current book. '
              'Requires text and CFI position (use resolve_cfi to get it). '
              'Optionally attach a note and set color.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'text': {
                'type': 'string',
                'description': 'The text content to highlight.',
              },
              'cfi': {
                'type': 'string',
                'description':
                    'EPUB CFI position string. Use resolve_cfi tool to find this.',
              },
              'note': {
                'type': 'string',
                'description':
                    'Optional personal note to attach to the highlight.',
              },
              'color': {
                'type': 'string',
                'description':
                    'Hex color code without # (e.g., FFD700, FF0000, 66CCFF). '
                    'Available: 66CCFF (blue), FF0000 (red), 00FF00 (green), '
                    'EB3BFF (purple), FFD700 (gold). Default: FFD700.',
              },
            },
            'required': ['text', 'cfi'],
          },
        );

  final dynamic _ref;
  final AnnotationLedger? ledger;

  @override
  CreateHighlightInput parseInput(Map<String, dynamic> json) =>
      CreateHighlightInput.fromJson(json);

  @override
  FutureOr<Map<String, dynamic>> run(CreateHighlightInput input) async {
    final readingState = _ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No book is currently open');
    }

    final bookId = readingState.book?.id;
    if (bookId == null) {
      throw StateError('Current book has no ID');
    }

    final chapterTitle = readingState.chapterTitle ?? 'Unknown chapter';
    final color = _validateColor(input.color ?? 'FFD700');

    final bookNote = BookNote(
      bookId: bookId,
      content: input.text,
      cfi: input.cfi,
      chapter: chapterTitle,
      type: 'highlight',
      color: color,
      readerNote: input.note,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );

    final noteId = await BookNoteDao().save(bookNote);

    ledger?.addHighlight(
      text: input.text,
      chapterTitle: chapterTitle,
      note: input.note,
      color: color,
    );

    return {
      'id': noteId,
      'text': input.text,
      'chapter': chapterTitle,
      'color': color,
      'note': input.note,
    };
  }

  String _validateColor(String color) {
    const validColors = {'66CCFF', 'FF0000', '00FF00', 'EB3BFF', 'FFD700'};
    final cleaned = color.replaceAll('#', '').toUpperCase();
    return validColors.contains(cleaned) ? cleaned : 'FFD700';
  }
}

final AiToolDefinition createHighlightToolDefinition = AiToolDefinition(
  id: 'create_highlight',
  displayNameBuilder: (L10n l10n) => 'Create Highlight',
  descriptionBuilder: (L10n l10n) =>
      'Create a highlight annotation in the current book',
  build: (context) => CreateHighlightTool(context.ref, ledger: context.annotationLedger).tool,
  riskLevel: AiToolRiskLevel.write,
  scenes: const {AiToolScene.reading},
  isConcurrencySafe: false,
);
