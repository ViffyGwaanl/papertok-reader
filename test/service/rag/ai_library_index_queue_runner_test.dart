import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_runner.dart';
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
}
