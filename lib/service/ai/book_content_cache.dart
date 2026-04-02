import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// LRU cache for book chapter content.
///
/// When the AI agent reads the same chapter multiple times in a conversation,
/// this cache detects unchanged content and avoids re-transmitting it as
/// tool output, saving significant token costs.
///
/// Inspired by Claude Code's `fileStateCache.ts`.
class BookContentCache {
  BookContentCache({this.maxEntries = 20});

  final int maxEntries;
  final _cache = LinkedHashMap<String, _CacheEntry>();

  /// Returns `true` if the content at [bookId]+[chapterHref] has NOT changed
  /// since the last time it was cached. When unchanged, the caller should
  /// return a short "[unchanged]" marker instead of the full content.
  ///
  /// Returns `false` if the content is new or has changed (caller should
  /// return the full content and call [put] afterwards).
  bool isUnchanged(String bookId, String chapterHref, String content) {
    final key = _key(bookId, chapterHref);
    final entry = _cache[key];
    if (entry == null) return false;

    final currentHash = _hash(content);
    return entry.contentHash == currentHash;
  }

  /// Store content in the cache.
  void put(String bookId, String chapterHref, String content) {
    final key = _key(bookId, chapterHref);

    // Remove and re-insert to maintain LRU order
    _cache.remove(key);
    _cache[key] = _CacheEntry(
      contentHash: _hash(content),
      contentLength: content.length,
    );

    // Evict oldest entries if over capacity
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Clear the entire cache (e.g. when switching books).
  void clear() => _cache.clear();

  /// Number of cached entries.
  int get length => _cache.length;

  String _key(String bookId, String chapterHref) => '$bookId|$chapterHref';

  String _hash(String content) =>
      md5.convert(utf8.encode(content)).toString();
}

class _CacheEntry {
  const _CacheEntry({
    required this.contentHash,
    required this.contentLength,
  });

  final String contentHash;
  final int contentLength;
}
