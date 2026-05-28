import 'dart:async';

import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:papertok_reader/utils/log/common.dart';

class AiIndexCancellationToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef AiLibraryIndexJobExecutor = Future<void> Function(
  int bookId, {
  required bool rebuild,
  required AiIndexCancellationToken cancelToken,
  required Future<void> Function(AiLibraryIndexJobProgress progress) onProgress,
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

  Future<void> requeueRunningJobs() async {
    for (final token in _tokens.values) {
      token.cancel();
    }

    final jobs = await _repo.listJobs();
    for (final job in jobs) {
      if (job.status == AiLibraryIndexJobStatus.running) {
        await _repo.updateJob(
          job.id,
          status: AiLibraryIndexJobStatus.queued,
          progress: 0,
          clearCurrentChapter: true,
          clearProgressDetails: true,
        );
      }
    }
  }

  Future<AiLibraryIndexJob?> runOnce({bool Function()? shouldRun}) async {
    if (shouldRun != null && !shouldRun()) return null;

    final jobs = await _repo.listJobs();
    final next = jobs
        .where((j) => j.status == AiLibraryIndexJobStatus.queued)
        .toList(growable: false)
        .lastOrNull;

    if (next == null) return null;

    await _repo.updateJob(
      next.id,
      status: AiLibraryIndexJobStatus.running,
      progress: 0,
      clearCurrentChapter: true,
      clearProgressDetails: true,
      clearLastError: true,
    );

    final token = AiIndexCancellationToken();
    _tokens[next.id] = token;

    try {
      if (shouldRun != null && !shouldRun()) {
        token.cancel();
        await _repo.updateJob(
          next.id,
          status: AiLibraryIndexJobStatus.queued,
          progress: 0,
          clearCurrentChapter: true,
          clearProgressDetails: true,
        );
        return null;
      }

      await _executor(
        next.bookId,
        rebuild: next.forceRebuild,
        cancelToken: token,
        onProgress: (p) {
          return _repo.updateJob(
            next.id,
            progress: p.progress,
            phase: p.phase,
            doneChapters: p.doneChapters,
            totalChapters: p.totalChapters,
            doneChunks: p.doneChunks,
            totalChunks: p.totalChunks,
            currentChapterDoneChunks: p.currentChapterDoneChunks,
            currentChapterTotalChunks: p.currentChapterTotalChunks,
            embeddingBatchIndex: p.embeddingBatchIndex,
            embeddingBatchTotal: p.embeddingBatchTotal,
            lastEmbeddingBatchSize: p.lastEmbeddingBatchSize,
            lastEmbeddingDim: p.lastEmbeddingDim,
            currentChapterHref: p.currentChapterHref,
            currentChapterTitle: p.currentChapterTitle,
          );
        },
      );

      if (token.cancelled) {
        await _markCancelledUnlessRequeued(next.id);
      } else {
        await _repo.updateJob(next.id,
            status: AiLibraryIndexJobStatus.succeeded);
      }
    } catch (e, st) {
      if (!token.cancelled) {
        AnxLog.warning(
          'AiLibraryIndexQueueRunner: job failed id=${next.id} $e',
          st,
        );
      }
      final fresh = await _repo.getJob(next.id);
      final retryCount = fresh?.retryCount ?? next.retryCount;
      final maxRetries = fresh?.maxRetries ?? next.maxRetries;

      if (token.cancelled) {
        await _markCancelledUnlessRequeued(next.id);
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

  Future<void> _markCancelledUnlessRequeued(int jobId) async {
    final fresh = await _repo.getJob(jobId);
    if (fresh?.status == AiLibraryIndexJobStatus.queued) return;
    await _repo.updateJob(jobId, status: AiLibraryIndexJobStatus.cancelled);
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
