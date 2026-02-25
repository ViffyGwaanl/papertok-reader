import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/rag/library/ai_headless_reader_bridge.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiHeadlessReaderBridgeService {
  AiHeadlessReaderBridgeService(
    this.ref, {
    BooksRepository? booksRepository,
    Duration? idleTimeout,
  })  : _booksRepository = booksRepository ?? const BooksRepository(),
        _idleTimeout = idleTimeout ?? const Duration(minutes: 3);

  final Ref ref;
  final BooksRepository _booksRepository;
  final Duration _idleTimeout;

  final _lock = _AsyncLock();

  AiHeadlessReaderBridge? _active;
  Timer? _disposeTimer;

  Future<AiHeadlessReaderBridge> open(int bookId) {
    return _lock.synchronized(() async {
      _cancelDisposeTimer();

      final book = await _resolveBook(bookId);

      final existing = _active;
      if (existing != null &&
          existing.book.id == book.id &&
          existing.isActive) {
        return existing;
      }

      await existing?.dispose();
      final bridge = AiHeadlessReaderBridge(book: book);
      _active = bridge;
      await bridge.ensureInitialized();
      return bridge;
    });
  }

  void scheduleDispose() {
    _cancelDisposeTimer();
    _disposeTimer = Timer(_idleTimeout, () {
      unawaited(dispose());
    });
  }

  Future<void> dispose() {
    return _lock.synchronized(() async {
      _cancelDisposeTimer();
      final bridge = _active;
      _active = null;
      await bridge?.dispose();
    });
  }

  void _cancelDisposeTimer() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  Future<Book> _resolveBook(int bookId) async {
    if (bookId <= 0) {
      throw ArgumentError('bookId must be greater than zero');
    }

    final books = await _booksRepository.fetchByIds([bookId]);
    final book = books[bookId];
    if (book == null) {
      throw StateError('Book with id=$bookId not found.');
    }
    if (book.isDeleted) {
      throw StateError('Book with id=$bookId has been deleted.');
    }

    AnxLog.info(
      'AiHeadlessReaderBridgeService: open bookId=${book.id} title="${book.title}"',
    );

    return book;
  }
}

final aiHeadlessReaderBridgeProvider = Provider<AiHeadlessReaderBridgeService>(
  (ref) => AiHeadlessReaderBridgeService(ref),
);

class _AsyncLock {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final prev = _tail;
    final completer = Completer<void>();
    _tail = prev.then((_) => completer.future);

    await prev;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
