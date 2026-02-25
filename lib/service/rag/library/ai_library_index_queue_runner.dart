import 'dart:async';

import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:anx_reader/utils/log/common.dart';

class AiIndexCancellationToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef AiLibraryIndexJobExecutor = Future<void> Function(
  int bookId, {
  required AiIndexCancellationToken cancelToken,
  required void Function(double progress, String? href, String? title)
      onProgress,
});

/// Pure runner for the library indexing queue.
///
/// - No Flutter/UI dependency
/// - DB-backed (via [AiLibraryIndexQueueRepository])
/// - Concurrency handled by the caller (service) by ensuring only one runner
///   loop is active.
class AiLibraryIndexQueueRunner {
  AiLibraryIndexQueueRunner({
    required AiLibraryIndexQueueRepository repository,
    required AiLibraryIndexJobExecutor executor,
  })  : _repo = repository,
        _executor = executor;

  final AiLibraryIndexQueueRepository _repo;
  final AiLibraryIndexJobExecutor _executor;

  final Map<int, AiIndexCancellationToken> _tokens = {};

  Future<void> normalizeAfterRestart() async {
    final jobs = await _repo.listJobs();
    for (final j in jobs) {
      if (j.status == AiLibraryIndexJobStatus.running) {
        await _repo.updateJob(j.id, status: AiLibraryIndexJobStatus.queued);
      }
    }
  }

  Future<void> cancelJob(int jobId) async {
    _tokens[jobId]?.cancel();
    await _repo.updateJob(jobId, status: AiLibraryIndexJobStatus.cancelled);
  }

  Future<AiLibraryIndexJob?> runOnce() async {
    final jobs = await _repo.listJobs();
    final next = jobs
        .where((j) => j.status == AiLibraryIndexJobStatus.queued)
        .toList(growable: false)
        .lastOrNull;

    if (next == null) return null;

    await _repo.updateJob(next.id, status: AiLibraryIndexJobStatus.running);

    final token = AiIndexCancellationToken();
    _tokens[next.id] = token;

    try {
      await _executor(
        next.bookId,
        cancelToken: token,
        onProgress: (p, href, title) {
          unawaited(
            _repo.updateJob(
              next.id,
              progress: p,
              currentChapterHref: href,
              currentChapterTitle: title,
            ),
          );
        },
      );

      if (token.cancelled) {
        await _repo.updateJob(next.id,
            status: AiLibraryIndexJobStatus.cancelled);
      } else {
        await _repo.updateJob(next.id,
            status: AiLibraryIndexJobStatus.succeeded);
      }
    } catch (e, st) {
      AnxLog.warning(
        'AiLibraryIndexQueueRunner: job failed id=${next.id} $e',
        st,
      );
      final fresh = await _repo.getJob(next.id);
      final retryCount = fresh?.retryCount ?? next.retryCount;
      final maxRetries = fresh?.maxRetries ?? next.maxRetries;

      if (token.cancelled) {
        await _repo.updateJob(next.id,
            status: AiLibraryIndexJobStatus.cancelled);
      } else if (retryCount < maxRetries) {
        await _repo.updateJob(
          next.id,
          status: AiLibraryIndexJobStatus.queued,
          retryCount: retryCount + 1,
          lastError: e.toString(),
        );
      } else {
        await _repo.updateJob(
          next.id,
          status: AiLibraryIndexJobStatus.failed,
          lastError: e.toString(),
        );
      }
    } finally {
      _tokens.remove(next.id);
    }

    return _repo.getJob(next.id);
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
