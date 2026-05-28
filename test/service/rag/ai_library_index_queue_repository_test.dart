import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AiLibraryIndexQueueRepository can enqueue and update a job', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    final job = await repo.enqueueBook(42, maxRetries: 1, forceRebuild: true);
    expect(job.bookId, 42);
    expect(job.status, AiLibraryIndexJobStatus.queued);
    expect(job.forceRebuild, isTrue);

    final updated = await repo.updateJob(
      job.id,
      status: AiLibraryIndexJobStatus.running,
      retryCount: 1,
      progress: 0.5,
      phase: 'embed',
      doneChapters: 3,
      totalChapters: 10,
      doneChunks: 24,
      totalChunks: 80,
      currentChapterDoneChunks: 9,
      currentChapterTotalChunks: 20,
      embeddingBatchIndex: 2,
      embeddingBatchTotal: 5,
      lastEmbeddingBatchSize: 16,
      lastEmbeddingDim: 1024,
      currentChapterHref: 'c1.xhtml',
      currentChapterTitle: 'C1',
      lastError: 'boom',
    );

    expect(updated.status, AiLibraryIndexJobStatus.running);
    expect(updated.retryCount, 1);
    expect(updated.progress, 0.5);
    expect(updated.phase, 'embed');
    expect(updated.doneChapters, 3);
    expect(updated.totalChapters, 10);
    expect(updated.doneChunks, 24);
    expect(updated.totalChunks, 80);
    expect(updated.currentChapterDoneChunks, 9);
    expect(updated.currentChapterTotalChunks, 20);
    expect(updated.embeddingBatchIndex, 2);
    expect(updated.embeddingBatchTotal, 5);
    expect(updated.lastEmbeddingBatchSize, 16);
    expect(updated.lastEmbeddingDim, 1024);
    expect(updated.currentChapterHref, 'c1.xhtml');
    expect(updated.currentChapterTitle, 'C1');
    expect(updated.lastError, 'boom');
    expect(updated.forceRebuild, isTrue);

    final list = await repo.listJobs();
    expect(list.length, 1);
  });

  test('AiLibraryIndexQueueRepository can clear transient job fields',
      () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    final job = await repo.enqueueBook(43, maxRetries: 1);
    await repo.updateJob(
      job.id,
      status: AiLibraryIndexJobStatus.running,
      progress: 0.75,
      phase: 'embed',
      doneChapters: 2,
      totalChapters: 4,
      doneChunks: 8,
      totalChunks: 12,
      currentChapterDoneChunks: 3,
      currentChapterTotalChunks: 4,
      embeddingBatchIndex: 1,
      embeddingBatchTotal: 2,
      lastEmbeddingBatchSize: 4,
      lastEmbeddingDim: 1024,
      currentChapterHref: 'c1.xhtml',
      currentChapterTitle: 'C1',
      lastError: 'previous failure',
    );

    final cleared = await repo.updateJob(
      job.id,
      status: AiLibraryIndexJobStatus.queued,
      progress: 0,
      clearCurrentChapter: true,
      clearProgressDetails: true,
      clearLastError: true,
    );

    expect(cleared.status, AiLibraryIndexJobStatus.queued);
    expect(cleared.progress, 0);
    expect(cleared.phase, isNull);
    expect(cleared.doneChapters, 0);
    expect(cleared.totalChapters, 0);
    expect(cleared.doneChunks, 0);
    expect(cleared.totalChunks, 0);
    expect(cleared.currentChapterDoneChunks, 0);
    expect(cleared.currentChapterTotalChunks, 0);
    expect(cleared.embeddingBatchIndex, 0);
    expect(cleared.embeddingBatchTotal, 0);
    expect(cleared.lastEmbeddingBatchSize, 0);
    expect(cleared.lastEmbeddingDim, 0);
    expect(cleared.currentChapterHref, isNull);
    expect(cleared.currentChapterTitle, isNull);
    expect(cleared.lastError, isNull);
  });
}
