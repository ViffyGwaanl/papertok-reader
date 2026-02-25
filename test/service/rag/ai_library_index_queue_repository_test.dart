import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AiLibraryIndexQueueRepository can enqueue and update a job', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final repo = AiLibraryIndexQueueRepository(database: db);

    final job = await repo.enqueueBook(42, maxRetries: 1);
    expect(job.bookId, 42);
    expect(job.status, AiLibraryIndexJobStatus.queued);

    final updated = await repo.updateJob(
      job.id,
      status: AiLibraryIndexJobStatus.running,
      retryCount: 1,
      progress: 0.5,
      currentChapterHref: 'c1.xhtml',
      currentChapterTitle: 'C1',
      lastError: 'boom',
    );

    expect(updated.status, AiLibraryIndexJobStatus.running);
    expect(updated.retryCount, 1);
    expect(updated.progress, 0.5);
    expect(updated.currentChapterHref, 'c1.xhtml');
    expect(updated.currentChapterTitle, 'C1');
    expect(updated.lastError, 'boom');

    final list = await repo.listJobs();
    expect(list.length, 1);
  });
}
