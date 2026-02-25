class PaperReaderReaderIntent {
  const PaperReaderReaderIntent({
    required this.bookId,
    this.cfi,
    this.href,
  });

  final int bookId;
  final String? cfi;
  final String? href;

  bool get hasTarget =>
      (cfi != null && cfi!.trim().isNotEmpty) ||
      (href != null && href!.trim().isNotEmpty);

  static PaperReaderReaderIntent? tryParse(Uri uri) {
    if (uri.scheme.toLowerCase() != 'paperreader') return null;
    if (uri.host.toLowerCase() != 'reader') return null;

    // Expected: paperreader://reader/open?bookId=123&cfi=... or &href=...
    final seg0 = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (seg0.toLowerCase() != 'open') return null;

    final rawBookId = (uri.queryParameters['bookId'] ?? '').trim();
    final bookId = int.tryParse(rawBookId);
    if (bookId == null || bookId <= 0) return null;

    final cfi = (uri.queryParameters['cfi'] ?? '').trim();
    final href = (uri.queryParameters['href'] ?? '').trim();

    return PaperReaderReaderIntent(
      bookId: bookId,
      cfi: cfi.isEmpty ? null : cfi,
      href: href.isEmpty ? null : href,
    );
  }

  Uri toUri() {
    final qp = <String, String>{
      'bookId': bookId.toString(),
    };
    if (cfi != null && cfi!.trim().isNotEmpty) {
      qp['cfi'] = cfi!.trim();
    }
    if (href != null && href!.trim().isNotEmpty) {
      qp['href'] = href!.trim();
    }

    return Uri(
      scheme: 'paperreader',
      host: 'reader',
      path: '/open',
      queryParameters: qp,
    );
  }
}
