import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';

void main() {
  test('progress includes current chapter embedding chunk fraction', () {
    const progress = AiBookIndexProgress(
      phase: 'embed',
      doneChapters: 1,
      totalChapters: 4,
      doneChunks: 30,
      totalChunks: 80,
      currentChapterDoneChunks: 5,
      currentChapterTotalChunks: 10,
    );

    expect(progress.progress, closeTo(0.375, 0.0001));
  });
}
