import 'dart:async';

import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/rag/ai_book_indexer.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_repository.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_runner.dart';
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

    unawaited(_init());
  }

  final Ref ref;
  final AiLibraryIndexQueueRepository _repo;
  final AiIndexDatabase _database;
  final BooksRepository _booksRepository;

  late final AiLibraryIndexQueueRunner _runner;

  bool _running = false;
  bool _paused = false;
  int? _activeJobId;

  Future<void> _init() async {
    await _runner.normalizeAfterRestart();
    await refresh();
    unawaited(_tick());
  }

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

  Future<List<AiLibraryIndexJob>> enqueueBooks(Iterable<int> bookIds) async {
    final out = <AiLibraryIndexJob>[];
    for (final id in bookIds.where((e) => e > 0)) {
      out.add(await _repo.enqueueBook(id, maxRetries: 1));
    }
    await refresh();
    unawaited(_tick());
    return out;
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
    await _runner.cancelJob(jobId);
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
        final jobs = await _repo.listJobs();
        final next = jobs.firstWhere(
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

        await _runner.runOnce();

        _activeJobId = null;
        state = state.copyWith(activeJobId: null);

        await refresh();
      }
    } finally {
      _running = false;
      await refresh();
    }
  }

  Future<void> _executeJob(
    int bookId, {
    required AiIndexCancellationToken cancelToken,
    required void Function(double progress, String? href, String? title)
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

    await indexer.buildBook(
      book: book,
      rebuild: true,
      onProgress: (p) {
        if (cancelToken.cancelled) return;
        onProgress(p.progress, p.currentChapterHref, p.currentChapterTitle);
      },
    );
  }
}

final aiLibraryIndexQueueProvider =
    StateNotifierProvider<AiLibraryIndexQueueService, AiLibraryIndexQueueState>(
  (ref) => AiLibraryIndexQueueService(ref),
);
