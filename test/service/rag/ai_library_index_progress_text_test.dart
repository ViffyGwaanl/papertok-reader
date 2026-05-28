import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_progress_text.dart';

void main() {
  test('formats detailed embedding progress in Chinese', () {
    final text = AiLibraryIndexProgressText.detail(
      job: AiLibraryIndexJob(
        id: 1,
        bookId: 42,
        status: AiLibraryIndexJobStatus.running,
        retryCount: 0,
        maxRetries: 1,
        progress: 0.375,
        phase: 'embed',
        doneChapters: 1,
        totalChapters: 4,
        doneChunks: 30,
        totalChunks: 80,
        currentChapterDoneChunks: 5,
        currentChapterTotalChunks: 10,
        embeddingBatchIndex: 2,
        embeddingBatchTotal: 5,
        lastEmbeddingBatchSize: 16,
        lastEmbeddingDim: 1024,
        currentChapterTitle: '第二章',
      ),
      languageCode: 'zh',
    );

    expect(text, contains('生成向量'));
    expect(text, contains('章节 1/4'));
    expect(text, contains('当前章节 chunks 5/10'));
    expect(text, contains('Embedding 批次 2/5'));
    expect(text, contains('输出 16 个向量 x 1024 维'));
    expect(text, contains('当前 第二章'));
  });

  test('formats compact active progress in Chinese', () {
    final text = AiLibraryIndexProgressText.compact(
      job: const AiLibraryIndexJob(
        id: 1,
        bookId: 42,
        status: AiLibraryIndexJobStatus.running,
        retryCount: 0,
        maxRetries: 1,
        progress: 0.375,
        phase: 'embed',
        doneChapters: 1,
        totalChapters: 4,
        doneChunks: 30,
        totalChunks: 80,
        currentChapterDoneChunks: 5,
        currentChapterTotalChunks: 10,
        embeddingBatchIndex: 2,
        embeddingBatchTotal: 5,
        lastEmbeddingBatchSize: 16,
        lastEmbeddingDim: 1024,
      ),
      languageCode: 'zh',
    );

    expect(text, contains('索引 #42'));
    expect(text, contains('38%'));
    expect(text, contains('Embedding 2/5'));
    expect(text, contains('输出 16x1024'));
  });
}
