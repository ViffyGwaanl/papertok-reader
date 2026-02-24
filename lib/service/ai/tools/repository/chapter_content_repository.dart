import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:riverpod/riverpod.dart';

class ChapterContentRepository {
  const ChapterContentRepository();

  static const int _minLimit = 500;
  static const int _maxLimit = 12000;

  int? _resolveLimit(int? value) {
    if (value == null) {
      return null;
    }
    if (value <= 0) {
      return null;
    }
    return value.clamp(_minLimit, _maxLimit);
  }

  Future<String> fetchCurrent(
    Ref ref, {
    int? maxCharacters,
  }) async {
    final readingState = ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No active reading session.');
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    if (handlers == null) {
      throw StateError('Reader bridge is not available.');
    }

    final limit = _resolveLimit(maxCharacters);
    final content = await handlers.fetchCurrentChapter(maxCharacters: limit);
    return _sanitizeContent(content, limit);
  }

  Future<String> fetchByHref(
    Ref ref, {
    required String href,
    int? maxCharacters,
  }) async {
    final normalizedHref = href.trim();
    if (normalizedHref.isEmpty) {
      throw ArgumentError('href must not be empty');
    }

    final readingState = ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No active reading session.');
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    if (handlers == null) {
      throw StateError('Reader bridge is not available.');
    }

    final limit = _resolveLimit(maxCharacters);
    final content = await handlers.fetchChapterByHref(
      normalizedHref,
      maxCharacters: limit,
    );
    return _sanitizeContent(content, limit);
  }

  static const int _bookMaxLimit = 120000;

  int? _resolveBookLimit(int? value) {
    if (value == null) return null;
    if (value <= 0) return null;
    return value.clamp(_minLimit, _bookMaxLimit);
  }

  Future<Map<String, dynamic>> fetchBookContent(
    Ref ref, {
    int? maxCharacters,
    int? stopAtCharacters,
    bool includeHeadings = false,
  }) async {
    final readingState = ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No active reading session.');
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    if (handlers == null) {
      throw StateError('Reader bridge is not available.');
    }

    final fetcher = handlers.fetchBookContent;
    if (fetcher == null) {
      throw StateError('Book content bridge is not available.');
    }

    final limit = _resolveBookLimit(maxCharacters);
    final stop = _resolveBookLimit(stopAtCharacters);

    final result = await fetcher(
      maxCharacters: limit,
      stopAtCharacters: stop,
      includeHeadings: includeHeadings,
    );

    final content = (result['content'] is String)
        ? _sanitizeContent(result['content'] as String, limit)
        : '';

    return {
      ...result,
      'content': content,
      'charCount': content.length,
    };
  }

  Future<Map<String, dynamic>> resolveCfi(
    Ref ref,
    String cfi,
  ) async {
    final normalized = cfi.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('cfi must not be empty');
    }

    final readingState = ref.read(currentReadingProvider);
    if (!readingState.isReading) {
      throw StateError('No active reading session.');
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    if (handlers == null) {
      throw StateError('Reader bridge is not available.');
    }

    final resolver = handlers.resolveCfi;
    if (resolver == null) {
      throw StateError('CFI resolver bridge is not available.');
    }

    return await resolver(normalized);
  }

  String _sanitizeContent(String content, int? limit) {
    final trimmed = content.trim();
    if (limit == null || trimmed.length <= limit) {
      return trimmed;
    }
    return trimmed.substring(0, limit);
  }
}
