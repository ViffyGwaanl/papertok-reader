import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_contextual_chunker.dart';
import 'package:papertok_reader/service/rag/ai_index_chapter_plan.dart';

void main() {
  test('contextual chunker separates evidence text from embedding input', () {
    const chapter = AiIndexChapter(
      href: 'Text/chapter1.xhtml',
      title: 'Chapter 1',
      chapterOrder: 2,
      tocLevel: 1,
      tocPath: 'Part I / Chapter 1',
    );
    const builder = AiContextualChunkBuilder();

    final chunk = builder.build(
      bookTitle: 'Example Book',
      chapter: chapter,
      chunkText: 'The original paragraph.',
      chunkIndex: 3,
      totalChunks: 8,
      embeddingModel: 'test-embedding',
    );

    expect(AiContextualChunkBuilder.progressPhase, 'contextualize');
    expect(chunk.rawText, 'The original paragraph.');
    expect(chunk.contextText, contains('Example Book'));
    expect(chunk.contextText, contains('Part I / Chapter 1'));
    expect(chunk.embeddingText, contains(chunk.contextText));
    expect(chunk.embeddingText, contains(chunk.rawText));
    expect(chunk.embeddingInputHash, hasLength(64));
  });
}
