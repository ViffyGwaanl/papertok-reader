import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:papertok_reader/service/rag/ai_index_chapter_plan.dart';

class AiContextualChunk {
  const AiContextualChunk({
    required this.rawText,
    required this.contextText,
    required this.embeddingText,
    required this.embeddingInputHash,
  });

  final String rawText;
  final String contextText;
  final String embeddingText;
  final String embeddingInputHash;
}

class AiContextualChunkBuilder {
  const AiContextualChunkBuilder();

  static const String progressPhase = 'contextualize';
  static const String contextModel = 'local-context-v1';
  static const int contextVersion = 1;

  AiContextualChunk build({
    required String bookTitle,
    required AiIndexChapter chapter,
    required String chunkText,
    required int chunkIndex,
    required int totalChunks,
    required String embeddingModel,
  }) {
    final rawText = chunkText.trim();
    final chapterTitle = chapter.title.trim();
    final tocPath = chapter.tocPath.trim();
    final contextLines = <String>[
      if (bookTitle.trim().isNotEmpty) 'Book: ${bookTitle.trim()}',
      if (chapterTitle.isNotEmpty) 'Chapter: $chapterTitle',
      if (tocPath.isNotEmpty && tocPath != chapterTitle) 'Path: $tocPath',
      'Chunk: ${chunkIndex + 1}/${totalChunks <= 0 ? 1 : totalChunks}',
    ];
    final contextText = contextLines.join('\n');
    final embeddingText =
        contextText.isEmpty ? rawText : '$contextText\n\n$rawText';
    final embeddingInputHash = sha256
        .convert(utf8.encode('$embeddingModel\n$contextModel\n$embeddingText'))
        .toString();

    return AiContextualChunk(
      rawText: rawText,
      contextText: contextText,
      embeddingText: embeddingText,
      embeddingInputHash: embeddingInputHash,
    );
  }
}
