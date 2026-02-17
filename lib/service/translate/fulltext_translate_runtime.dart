import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/fulltext_translate_cache.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:crypto/crypto.dart';

String _sanitizeInlineFullTextTranslation(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Remove common code fences.
  s = s.replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\n'), '');
  s = s.replaceAll(RegExp(r'\n```$'), '');

  // Remove thinking blocks if any model leaks them.
  s = s.replaceAll(RegExp(r'<think>[\s\S]*?<\/think>', multiLine: true), '');

  // If the model returned HTML/XML-like tags, strip them.
  // Heuristic: only strip tags that look like markup (<p>, </div>, <!DOCTYPE ...>).
  final tagPattern = RegExp(r'<[a-zA-Z/!][^>]*>');
  final fullWidthTagPattern = RegExp(r'＜[a-zA-Z/!][^＞]*＞');
  final tagCount = tagPattern.allMatches(s).length;
  final fwTagCount = fullWidthTagPattern.allMatches(s).length;

  if (tagCount >= 1 || fwTagCount >= 1) {
    s = s.replaceAll(tagPattern, '');
    s = s.replaceAll(fullWidthTagPattern, '');
  }

  // Clean up extra whitespace introduced by stripping tags.
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return s.trim();
}

class FullTextTranslateRuntime {
  FullTextTranslateRuntime._();

  static final FullTextTranslateRuntime instance = FullTextTranslateRuntime._();

  // Default concurrency requirement confirmed by user.
  static const int defaultConcurrency = 4;

  final _Semaphore _semaphore = _Semaphore(defaultConcurrency);
  final Map<String, Future<String>> _inflight = {};

  String normalizeForCacheKey(String text) => _normalizeForCacheKey(text);

  String sanitize(String raw) => _sanitizeInlineFullTextTranslation(raw);

  String buildCacheKey({
    required int bookId,
    required TranslateService service,
    required LangListEnum from,
    required LangListEnum to,
    required String text,
  }) {
    final normalized = _normalizeForCacheKey(text);
    return sha1
        .convert(utf8.encode(
          'v1|book:$bookId|svc:${service.name}|from:${from.code}|to:${to.code}|$normalized',
        ))
        .toString();
  }

  Future<String> translate(
    TranslateService service,
    String text,
    LangListEnum from,
    LangListEnum to, {
    required int bookId,
    String? contextText,
    bool enableCache = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    // Cache key MUST include bookId to enable per-book clear.
    final key = buildCacheKey(
      bookId: bookId,
      service: service,
      from: from,
      to: to,
      text: text,
    );

    if (enableCache) {
      final cached = await FullTextTranslateCache.get(bookId, key);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final existing = _inflight[key];
    if (existing != null) {
      return await existing;
    }

    final future = _semaphore.withPermit(() async {
      // Extra retry layer for providers that return error strings (not exceptions).
      const maxAttempts = 2;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final result = await service.provider.translateTextOnly(
          text,
          from,
          to,
          contextText: contextText,
        );

        final sanitized = sanitize(result);

        final lower = sanitized.trim().toLowerCase();
        final looksBad = sanitized.trim().isEmpty ||
            lower.startsWith('error:') ||
            lower.contains('authentication failed') ||
            lower.contains('rate limit') ||
            lower.contains('ai service not configured') ||
            lower.contains('ai 服务未配置');

        if (!looksBad) {
          if (enableCache) {
            await FullTextTranslateCache.set(bookId, key, sanitized);
          }
          return sanitized;
        }

        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
          continue;
        }

        // Give up.
        return '';
      }

      return '';
    });

    _inflight[key] = future;

    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<void> clearBook(int bookId) async {
    await FullTextTranslateCache.clearBook(bookId);
  }

  String _normalizeForCacheKey(String text) {
    // Normalize in a way that keeps paragraph boundaries stable.
    // - Normalize CRLF
    // - Collapse spaces/tabs inside a line
    // - Collapse 3+ blank lines to 2
    final s = text.replaceAll('\r\n', '\n');
    final lines = s.split('\n').map((line) {
      return line.replaceAll(RegExp(r'[\t ]+'), ' ').trimRight();
    }).toList(growable: false);

    var normalized = lines.join('\n').trim();
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return normalized;
  }
}

class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _queue = Queue();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future.then((_) {
      _current++;
    });
  }

  void _release() {
    _current--;
    if (_current < 0) _current = 0;
    if (_queue.isNotEmpty && _current < _max) {
      final next = _queue.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }
}
