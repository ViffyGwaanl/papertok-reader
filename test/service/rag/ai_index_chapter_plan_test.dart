import 'package:papertok_reader/models/toc_item.dart';
import 'package:papertok_reader/service/rag/ai_contextual_chunker.dart';
import 'package:papertok_reader/service/rag/ai_index_chapter_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flattenToc preserves chapter order, levels, and readable paths', () {
    final toc = [
      TocItem(
        id: 'p1',
        href: 'Text/part1.xhtml',
        label: 'Part I',
        level: 0,
        startPage: 0,
        startPercentage: 0,
        subitems: [
          TocItem(
            id: 'c1',
            href: 'Text/chapter1.xhtml',
            label: 'Chapter 1',
            level: 1,
            startPage: 0,
            startPercentage: 0,
            subitems: const [],
          ),
          TocItem(
            id: 'c2',
            href: 'Text/chapter2.xhtml',
            label: 'Chapter 2',
            level: 1,
            startPage: 0,
            startPercentage: 0,
            subitems: const [],
          ),
        ],
      ),
      TocItem(
        id: 'dupe',
        href: 'Text/chapter1.xhtml',
        label: 'Duplicate Chapter 1',
        level: 0,
        startPage: 0,
        startPercentage: 0,
        subitems: const [],
      ),
    ];

    final chapters = AiIndexChapterPlan.flattenToc(toc);

    expect(chapters.map((c) => c.href), [
      'Text/part1.xhtml',
      'Text/chapter1.xhtml',
      'Text/chapter2.xhtml',
    ]);
    expect(chapters.map((c) => c.chapterOrder), [0, 1, 2]);
    expect(chapters.map((c) => c.tocLevel), [0, 1, 1]);
    expect(chapters[1].tocPath, 'Part I / Chapter 1');
    expect(chapters[2].tocPath, 'Part I / Chapter 2');
  });

  test('contextual chunk stores separate raw text and embedding input', () {
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

    expect(chunk.rawText, 'The original paragraph.');
    expect(chunk.contextText, contains('Example Book'));
    expect(chunk.contextText, contains('Part I / Chapter 1'));
    expect(chunk.embeddingText, contains(chunk.contextText));
    expect(chunk.embeddingText, contains(chunk.rawText));
    expect(chunk.embeddingInputHash, hasLength(64));
  });
}
