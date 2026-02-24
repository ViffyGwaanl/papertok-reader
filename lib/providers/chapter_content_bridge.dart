import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CurrentChapterContentFetcher = Future<String> Function(
    {int? maxCharacters});
typedef ChapterContentByHrefFetcher = Future<String> Function(
  String href, {
  int? maxCharacters,
});

/// Resolve an EPUB CFI to the best-effort chapter metadata (e.g. TOC item).
typedef CfiResolver = Future<Map<String, dynamic>> Function(String cfi);

/// Retrieve full-book plain-text content from the active reader.
///
/// Intended for short-book "full context" workflows. Implementations should
/// support early-stopping via [stopAtCharacters] to avoid heavy work.
typedef BookContentFetcher = Future<Map<String, dynamic>> Function({
  int? maxCharacters,
  int? stopAtCharacters,
  bool includeHeadings,
});

class ChapterContentHandlers {
  const ChapterContentHandlers({
    required this.fetchCurrentChapter,
    required this.fetchChapterByHref,
    this.resolveCfi,
    this.fetchBookContent,
  });

  final CurrentChapterContentFetcher fetchCurrentChapter;
  final ChapterContentByHrefFetcher fetchChapterByHref;
  final CfiResolver? resolveCfi;
  final BookContentFetcher? fetchBookContent;
}

final chapterContentBridgeProvider =
    StateProvider<ChapterContentHandlers?>((ref) => null);
