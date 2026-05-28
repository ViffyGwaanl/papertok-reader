import 'package:papertok_reader/models/source_ref.dart';

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
    if (cfi.isEmpty && href.isEmpty) return null;

    return PaperReaderReaderIntent(
      bookId: bookId,
      cfi: cfi.isEmpty ? null : cfi,
      href: href.isEmpty ? null : href,
    );
  }

  static PaperReaderReaderIntent? fromSourceRef(SourceRef sourceRef) {
    final jumpLink = sourceRef.jumpLink?.trim();
    if (jumpLink != null && jumpLink.isNotEmpty) {
      final uri = Uri.tryParse(jumpLink);
      if (uri != null) {
        final parsed = tryParse(uri);
        if (parsed != null) return parsed;
      }
    }

    final bookId = sourceRef.bookId;
    if (bookId == null || bookId <= 0) return null;
    if (!sourceRef.hasBookAnchor) return null;
    return PaperReaderReaderIntent(
      bookId: bookId,
      cfi: _blankToNull(sourceRef.cfi),
      href: _blankToNull(sourceRef.href),
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

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class PaperReaderSourceJumpAudit {
  const PaperReaderSourceJumpAudit({
    required this.jumpableCount,
    required this.unavailableCount,
    required this.unresolvedIndexes,
  });

  final int jumpableCount;
  final int unavailableCount;
  final List<int> unresolvedIndexes;

  bool get allResolved => unresolvedIndexes.isEmpty;

  static PaperReaderSourceJumpAudit fromSourceRefs(
    Iterable<SourceRef> sourceRefs,
  ) {
    var jumpableCount = 0;
    var unavailableCount = 0;
    final unresolvedIndexes = <int>[];
    var index = 0;

    for (final ref in sourceRefs) {
      if (PaperReaderReaderIntent.fromSourceRef(ref) != null) {
        jumpableCount += 1;
      } else if (ref.hasUnavailableReason) {
        unavailableCount += 1;
      } else {
        unresolvedIndexes.add(index);
      }
      index += 1;
    }

    return PaperReaderSourceJumpAudit(
      jumpableCount: jumpableCount,
      unavailableCount: unavailableCount,
      unresolvedIndexes: unresolvedIndexes,
    );
  }
}
