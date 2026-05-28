import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_service.dart';

void main() {
  test('queue state summarizes overall progress and job counts', () {
    final state = AiLibraryIndexQueueState(
      jobs: [
        _job(1, AiLibraryIndexJobStatus.succeeded, progress: 1),
        _job(2, AiLibraryIndexJobStatus.running, progress: 0.5),
        _job(3, AiLibraryIndexJobStatus.queued, progress: 0),
        _job(4, AiLibraryIndexJobStatus.failed, progress: 0.25),
      ],
      activeJobId: 2,
    );

    expect(state.totalJobCount, 4);
    expect(state.succeededJobCount, 1);
    expect(state.runningJobCount, 1);
    expect(state.queuedJobCount, 1);
    expect(state.failedJobCount, 1);
    expect(state.finishedJobCount, 2);
    expect(state.overallProgress, 0.625);
  });
}

AiLibraryIndexJob _job(
  int id,
  AiLibraryIndexJobStatus status, {
  required double progress,
}) {
  return AiLibraryIndexJob(
    id: id,
    bookId: id,
    status: status,
    retryCount: 0,
    maxRetries: 1,
    progress: progress,
  );
}
