import 'dart:async';

import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/rag/ai_book_indexer.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiLibraryIndexQueueState {
  const AiLibraryIndexQueueState({
    required this.jobs,
    this.activeJobId,
    this.isPaused = false,
    this.lastError,
  });

  final List<AiLibraryIndexJob> jobs;
  final int? activeJobId;
  final bool isPaused;
  final String? lastError;

  AiLibraryIndexQueueState copyWith({
    List<AiLibraryIndexJob>? jobs,
    int? activeJobId,
    bool? isPaused,
    String? lastError,
  }) {
    return AiLibraryIndexQueueState(
      jobs: jobs ?? this.jobs,
      activeJobId: activeJobId ?? this.activeJobId,
      isPaused: isPaused ?? this.isPaused,
      lastError: lastError,
    );
  }

  static const empty = AiLibraryIndexQueueState(jobs: <AiLibraryIndexJob>[]);
}

class AiLibraryIndexQueueService
    extends StateNotifier<AiLibraryIndexQueueState> {
  AiLibraryIndexQueueService(this.ref, {AiIndexDatabase? database})
      : _repo = AiLibraryIndexQueueRepository(database: database),
        _database = database ?? AiIndexDatabase.instance,
        super(AiLibraryIndexQueueState.empty) {
    unawaited(refresh());
    // Best-effort: resume pending jobs after restart.
    unawaited(_tick());
  }

  final Ref ref;
  final AiLibraryIndexQueueRepository _repo;
  final AiIndexDatabase _database;

  bool _running = false;
  bool _paused = false;
  int? _activeJobId;

  Future<void> refresh() async {
    final jobs = await _repo.listJobs();
    state = state.copyWith(
      jobs: jobs,
      activeJobId: _activeJobId,
      isPaused: _paused,
    );
  }

  Future<AiLibraryIndexJob> enqueueBook(int bookId) async {
    final job = await _repo.enqueueBook(bookId, maxRetries: 1);
    await refresh();
    unawaited(_tick());
    return job;
  }

  Future<void> pause() async {
    _paused = true;
    state = state.copyWith(isPaused: true);
  }

  Future<void> resume() async {
    _paused = false;
    state = state.copyWith(isPaused: false);
    unawaited(_tick());
  }

  Future<void> cancelJob(int jobId) async {
    // If cancelling active job, mark cancelled and stop after current unit.
    final job = await _repo.getJob(jobId);
    if (job == null) return;
    await _repo.updateJob(jobId, status: AiLibraryIndexJobStatus.cancelled);
    if (_activeJobId == jobId) {
      _activeJobId = null;
    }
    await refresh();
  }

  Future<void> clearFinishedJobs() async {
    final jobs = await _repo.listJobs();
    for (final j in jobs) {
      if (j.status == AiLibraryIndexJobStatus.succeeded ||
          j.status == AiLibraryIndexJobStatus.failed ||
          j.status == AiLibraryIndexJobStatus.cancelled) {
        await _repo.deleteJob(j.id);
      }
    }
    await refresh();
  }

  Future<void> _tick() async {
    if (_running || _paused) return;
    _running = true;
    try {
      while (!_paused) {
        final runnable = await _repo.listRunnableJobs();
        // Pick first queued job.
        final next = runnable.firstWhere(
          (j) => j.status == AiLibraryIndexJobStatus.queued,
          orElse: () => const AiLibraryIndexJob(
            id: -1,
            bookId: -1,
            status: AiLibraryIndexJobStatus.failed,
            retryCount: 0,
            maxRetries: 1,
            progress: 0,
          ),
        );
        if (next.id <= 0) break;

        _activeJobId = next.id;
        state = state.copyWith(activeJobId: _activeJobId);

        await _runJob(next);

        _activeJobId = null;
        state = state.copyWith(activeJobId: null);
      }
    } finally {
      _running = false;
      await refresh();
    }
  }

  Future<void> _runJob(AiLibraryIndexJob job) async {
    // Move to running.
    await _repo.updateJob(job.id, status: AiLibraryIndexJobStatus.running);
    await refresh();

    try {
      final indexer = AiBookIndexer(ref, database: _database);

      // TODO: resolve embeddingModel from user settings.
      await indexer.buildBook(
        book: (await BooksRepository().fetchByIds([job.bookId]))[job.bookId]!,
        rebuild: true,
        onProgress: (p) {
          unawaited(
            _repo.updateJob(
              job.id,
              progress: p.progress,
              currentChapterHref: p.currentChapterHref,
              currentChapterTitle: p.currentChapterTitle,
            ),
          );
        },
      );

      await _repo.updateJob(job.id, status: AiLibraryIndexJobStatus.succeeded);
    } catch (e, st) {
      AnxLog.warn('AiLibraryIndexQueue: job failed: ${job.id} $e\n$st');
      final fresh = await _repo.getJob(job.id);
      final retryCount = fresh?.retryCount ?? job.retryCount;
      final maxRetries = fresh?.maxRetries ?? job.maxRetries;
      if (retryCount < maxRetries) {
        await _repo.updateJob(
          job.id,
          status: AiLibraryIndexJobStatus.queued,
          retryCount: retryCount + 1,
          lastError: e.toString(),
        );
      } else {
        await _repo.updateJob(
          job.id,
          status: AiLibraryIndexJobStatus.failed,
          lastError: e.toString(),
        );
      }
    } finally {
      await refresh();
    }
  }
}

final aiLibraryIndexQueueProvider =
    StateNotifierProvider<AiLibraryIndexQueueService, AiLibraryIndexQueueState>(
  (ref) => AiLibraryIndexQueueService(ref),
);
