import 'dart:io';

import 'package:papertok_reader/dao/book.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/service/bookmark/bookmark_channel.dart';
import 'package:papertok_reader/utils/log/common.dart';

/// One-stop access helper for book file bytes.
///
/// - For legacy ("imported") books returns a bare [File] backed by
///   [Book.fileFullPath].
/// - For "inplace" books resolves the security-scoped bookmark, calls
///   `startAccessingSecurityScopedResource`, persists any refreshed
///   bookmark back to the DB, and releases the scope on [dispose].
class ScopedFileAccess {
  ScopedFileAccess._(this.path, this.book, this._token);

  final String path;
  final Book book;
  final String? _token;

  File get file => File(path);

  /// Paths currently held in scope. The local HTTP server consults this
  /// allow-list to permit serving files outside the sandbox base dir.
  static final Set<String> activeScopedPaths = <String>{};

  Future<void> dispose() async {
    activeScopedPaths.remove(path);
    if (_token != null) {
      try {
        await BookmarkChannel.instance.stopAccess(_token);
      } catch (e) {
        AnxLog.warning('ScopedFileAccess.dispose: $e');
      }
    }
  }

  static Future<ScopedFileAccess> open(Book book) async {
    if (!book.isInPlace || book.bookmarkData == null) {
      return ScopedFileAccess._(book.fileFullPath, book, null);
    }
    final scope = await BookmarkChannel.instance.startAccess(book.bookmarkData!);
    if (scope.isStale && scope.freshBookmark != null) {
      book.bookmarkData = scope.freshBookmark;
      await bookDao.updateBook(book);
    }
    activeScopedPaths.add(scope.path);
    return ScopedFileAccess._(scope.path, book, scope.token);
  }

  static Future<T> run<T>(Book book, Future<T> Function(File file) body) async {
    final handle = await open(book);
    try {
      return await body(handle.file);
    } finally {
      await handle.dispose();
    }
  }
}
