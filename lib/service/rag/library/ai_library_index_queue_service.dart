import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/tools/repository/books_repository.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_runner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Object _unsetQueueStateField = Object();

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

  AiLibraryIndexJob? get activeJob {
    final id = activeJobId;
    if (id == null) return null;
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  int get totalJobCount => jobs.length;

  int get queuedJobCount => _count(AiLibraryIndexJobStatus.queued);

  int get runningJobCount => _count(AiLibraryIndexJobStatus.running);

  int get pausedJobCount => _count(AiLibraryIndexJobStatus.paused);

  int get succeededJobCount => _count(AiLibraryIndexJobStatus.succeeded);

  int get failedJobCount => _count(AiLibraryIndexJobStatus.failed);

  int get cancelledJobCount => _count(AiLibraryIndexJobStatus.cancelled);

  int get finishedJobCount =>
      succeededJobCount + failedJobCount + cancelledJobCount;

  double get overallProgress {
    if (jobs.isEmpty) return 0;

    double completedWeight(AiLibraryIndexJob job) {
      switch (job.status) {
        case AiLibraryIndexJobStatus.succeeded:
        case AiLibraryIndexJobStatus.failed:
        case AiLibraryIndexJobStatus.cancelled:
          return 1;
        case AiLibraryIndexJobStatus.running:
        case AiLibraryIndexJobStatus.paused:
          return job.progress.clamp(0.0, 1.0).toDouble();
        case AiLibraryIndexJobStatus.queued:
          return 0;
      }
    }

    final done = jobs.fold<double>(0, (sum, job) => sum + completedWeight(job));
    return (done / jobs.length).clamp(0.0, 1.0).toDouble();
  }

  int _count(AiLibraryIndexJobStatus status) {
    return jobs.where((job) => job.status == status).length;
  }

  AiLibraryIndexQueueState copyWith({
    List<AiLibraryIndexJob>? jobs,
    Object? activeJobId = _unsetQueueStateField,
    bool? isPaused,
    Object? lastError = _unsetQueueStateField,
  }) {
    return AiLibraryIndexQueueState(
      jobs: jobs ?? this.jobs,
      activeJobId: activeJobId == _unsetQueueStateField
          ? this.activeJobId
          : activeJobId as int?,
      isPaused: isPaused ?? this.isPaused,
      lastError: lastError == _unsetQueueStateField
          ? this.lastError
          : lastError as String?,
    );
  }

  static const empty = AiLibraryIndexQueueState(jobs: <AiLibraryIndexJob>[]);
}

class AiLibraryIndexQueueService extends StateNotifier<AiLibraryIndexQueueState>
    with WidgetsBindingObserver {
  AiLibraryIndexQueueService(
    this.ref, {
    AiIndexDatabase? database,
    BooksRepository? booksRepository,
  })  : _repo = AiLibraryIndexQueueRepository(database: database),
        _database = database ?? AiIndexDatabase.instance,
        _booksRepository = booksRepository ?? const BooksRepository(),
        super(AiLibraryIndexQueueState.empty) {
    _runner = AiLibraryIndexQueueRunner(
      repository: _repo,
      executor: _executeJob,
    );

    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  final Ref ref;
  final AiLibraryIndexQueueRepository _repo;
  final AiIndexDatabase _database;
  final BooksRepository _booksRepository;

  late final AiLibraryIndexQueueRunner _runner;

  bool _running = false;
  bool _userPaused = false;
  bool _lifecyclePaused = false;

  bool get _paused => _userPaused || _lifecyclePaused;

  // UI refresh throttling while a job is running.
  int _lastProgressRefreshMs = 0;

  Future<void> _init() async {
    await _runner.normalizeAfterRestart();
    await refresh();
    unawaited(_tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_pauseForLifecycle());
        break;
      case AppLifecycleState.resumed:
        unawaited(_resumeFromLifecycle());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> refresh() async {
    final jobs = await _repo.listJobs();
    final active = jobs
        .where((j) => j.status == AiLibraryIndexJobStatus.running)
        .map((j) => j.id)
        .cast<int?>()
        .firstOrNull;

    state = state.copyWith(
      jobs: jobs,
      activeJobId: active,
      isPaused: _paused,
    );
  }

  Future<AiLibraryIndexJob> enqueueBook(
    int bookId, {
    bool forceRebuild = false,
  }) async {
    final job = await _repo.enqueueBook(
      bookId,
      maxRetries: 1,
      forceRebuild: forceRebuild,
    );
    await refresh();
    unawaited(_tick());
    return job;
  }

  Future<List<AiLibraryIndexJob>> enqueueBooks(
    Iterable<int> bookIds, {
    bool forceRebuild = false,
  }) async {
    final out = <AiLibraryIndexJob>[];
    for (final id in bookIds.where((e) => e > 0)) {
      out.add(
        await _repo.enqueueBook(
          id,
          maxRetries: 1,
          forceRebuild: forceRebuild,
        ),
      );
    }
    await refresh();
    unawaited(_tick());
    return out;
  }

  Future<void> pause() async {
    _userPaused = true;
    state = state.copyWith(isPaused: _paused);
  }

  Future<void> resume() async {
    _userPaused = false;
    state = state.copyWith(isPaused: _paused);
    if (!_paused) unawaited(_tick());
  }

  Future<void> _pauseForLifecycle() async {
    if (_lifecyclePaused) return;
    _lifecyclePaused = true;
    await _runner.requeueRunningJobs();
    await refresh();
  }

  Future<void> _resumeFromLifecycle() async {
    if (!_lifecyclePaused) return;
    _lifecyclePaused = false;
    if (!_running) {
      await _runner.normalizeAfterRestart();
    }
    await refresh();
    if (!_paused) unawaited(_tick());
  }

  Future<void> cancelJob(int jobId) async {
    await _runner.cancelJob(jobId);
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
        final executed = await _runner.runOnce(shouldRun: () => !_paused);
        await refresh();
        if (executed == null) break;
      }
    } finally {
      _running = false;
      await refresh();
    }
  }

  Future<void> _executeJob(
    int bookId, {
    required bool rebuild,
    required AiIndexCancellationToken cancelToken,
    required Future<void> Function(AiLibraryIndexJobProgress progress)
        onProgress,
  }) async {
    if (cancelToken.cancelled) return;

    final books = await _booksRepository.fetchByIds([bookId]);
    final book = books[bookId];
    if (book == null) {
      throw StateError('Book with id=$bookId not found');
    }

    if (cancelToken.cancelled) return;

    final indexer = AiBookIndexer(ref, database: _database);

    final providerId = Prefs().aiLibraryIndexProviderIdEffective;
    final embeddingModel = Prefs().aiLibraryIndexEmbeddingModelEffective;
    final pendingProgressWrites = <Future<void>>[];
    Object? progressWriteError;
    StackTrace? progressWriteStackTrace;

    void persistProgress(AiBookIndexProgress p) {
      if (cancelToken.cancelled) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldRefresh = now - _lastProgressRefreshMs > 300;
      if (shouldRefresh) {
        _lastProgressRefreshMs = now;
      }

      final write = onProgress(
        AiLibraryIndexJobProgress(
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
        ),
      ).then((_) async {
        if (shouldRefresh && !cancelToken.cancelled) {
          await refresh();
        }
      }).catchError((Object e, StackTrace st) {
        progressWriteError ??= e;
        progressWriteStackTrace ??= st;
      });
      pendingProgressWrites.add(write);
    }

    await indexer.buildBook(
      book: book,
      rebuild: rebuild,
      embeddingProviderId: providerId,
      embeddingModel: embeddingModel,
      embeddingBatchSize: Prefs().aiLibraryIndexEmbeddingBatchSize,
      embeddingsTimeoutSeconds: Prefs().aiLibraryIndexEmbeddingsTimeoutSeconds,
      chunkTargetChars: Prefs().aiLibraryIndexChunkTargetChars,
      chunkMaxChars: Prefs().aiLibraryIndexChunkMaxChars,
      chunkMinChars: Prefs().aiLibraryIndexChunkMinChars,
      chunkOverlapChars: Prefs().aiLibraryIndexChunkOverlapChars,
      maxChapterCharacters: Prefs().aiLibraryIndexMaxChapterCharacters,
      shouldCancel: () => cancelToken.cancelled,
      onProgress: persistProgress,
    );

    await Future.wait(pendingProgressWrites);
    if (progressWriteError != null) {
      Error.throwWithStackTrace(
        progressWriteError!,
        progressWriteStackTrace ?? StackTrace.current,
      );
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final aiLibraryIndexQueueProvider =
    StateNotifierProvider<AiLibraryIndexQueueService, AiLibraryIndexQueueState>(
  (ref) => AiLibraryIndexQueueService(ref),
);
