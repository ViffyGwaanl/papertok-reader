import 'dart:async';

import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('queue runner retries once then fails', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    await repo.enqueueBook(1, maxRetries: 1);

    var calls = 0;
    final runner = AiLibraryIndexQueueRunner(
      repository: repo,
      executor: (bookId, {required cancelToken, required onProgress}) async {
        calls += 1;
        throw StateError('boom');
      },
    );

    final j1 = await runner.runOnce();
    expect(j1, isNotNull);
    expect(j1!.status, AiLibraryIndexJobStatus.queued);
    expect(j1.retryCount, 1);

    final j2 = await runner.runOnce();
    expect(j2, isNotNull);
    expect(j2!.status, AiLibraryIndexJobStatus.failed);
    expect(j2.retryCount, 1);
    expect(calls, 2);
  });

  test('normalizeAfterRestart converts running to queued', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    final job = await repo.enqueueBook(2, maxRetries: 1);
    await repo.updateJob(job.id, status: AiLibraryIndexJobStatus.running);

    final runner = AiLibraryIndexQueueRunner(
      repository: repo,
      executor: (bookId, {required cancelToken, required onProgress}) async {},
    );

    await runner.normalizeAfterRestart();

    final refreshed = await repo.getJob(job.id);
    expect(refreshed, isNotNull);
    expect(refreshed!.status, AiLibraryIndexJobStatus.queued);
  });

  test('requeued active job stays queued after executor returns', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    final job = await repo.enqueueBook(3, maxRetries: 1);
    final started = Completer<void>();
    final release = Completer<void>();

    final runner = AiLibraryIndexQueueRunner(
      repository: repo,
      executor: (bookId, {required cancelToken, required onProgress}) async {
        started.complete();
        await release.future;
      },
    );

    final runFuture = runner.runOnce();
    await started.future;

    await runner.requeueRunningJobs();
    final requeued = await repo.getJob(job.id);
    expect(requeued!.status, AiLibraryIndexJobStatus.queued);

    release.complete();
    final result = await runFuture;

    expect(result, isNotNull);
    expect(result!.status, AiLibraryIndexJobStatus.queued);
  });

  test('runOnce requeues claimed job when shouldRun turns false', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    await repo.enqueueBook(4, maxRetries: 1);

    var executorCalls = 0;
    var shouldRunCalls = 0;
    final runner = AiLibraryIndexQueueRunner(
      repository: repo,
      executor: (bookId, {required cancelToken, required onProgress}) async {
        executorCalls += 1;
      },
    );

    final result = await runner.runOnce(
      shouldRun: () {
        shouldRunCalls += 1;
        return shouldRunCalls == 1;
      },
    );

    expect(result, isNull);
    expect(executorCalls, 0);

    final jobs = await repo.listJobs();
    final job = jobs.singleWhere((j) => j.bookId == 4);
    expect(job.status, AiLibraryIndexJobStatus.queued);
    expect(job.progress, 0);
  });

  test('runner persists detailed progress emitted by executor', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    await repo.enqueueBook(5, maxRetries: 1);

    final runner = AiLibraryIndexQueueRunner(
      repository: repo,
      executor: (bookId, {required cancelToken, required onProgress}) async {
        await onProgress(
          const AiLibraryIndexJobProgress(
            progress: 0.42,
            phase: 'embed',
            doneChapters: 2,
            totalChapters: 7,
            doneChunks: 16,
            totalChunks: 45,
            currentChapterDoneChunks: 4,
            currentChapterTotalChunks: 9,
            embeddingBatchIndex: 1,
            embeddingBatchTotal: 3,
            lastEmbeddingBatchSize: 8,
            lastEmbeddingDim: 1024,
            currentChapterHref: 'chapter-2.xhtml',
            currentChapterTitle: 'Chapter 2',
          ),
        );
      },
    );

    final result = await runner.runOnce();

    expect(result, isNotNull);
    expect(result!.status, AiLibraryIndexJobStatus.succeeded);
    expect(result.progress, 0.42);
    expect(result.phase, 'embed');
    expect(result.doneChapters, 2);
    expect(result.totalChapters, 7);
    expect(result.doneChunks, 16);
    expect(result.totalChunks, 45);
    expect(result.currentChapterDoneChunks, 4);
    expect(result.currentChapterTotalChunks, 9);
    expect(result.embeddingBatchIndex, 1);
    expect(result.embeddingBatchTotal, 3);
    expect(result.lastEmbeddingBatchSize, 8);
    expect(result.lastEmbeddingDim, 1024);
    expect(result.currentChapterHref, 'chapter-2.xhtml');
    expect(result.currentChapterTitle, 'Chapter 2');
  });
}
