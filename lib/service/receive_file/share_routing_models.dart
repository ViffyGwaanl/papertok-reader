import 'package:anx_reader/utils/book_file_types.dart';

/// A normalized payload coming from iOS Share Sheet / Android share intent.
///
/// This is intentionally UI-agnostic. Routing logic should be pure and tested.
class ShareInboundPayload {
  ShareInboundPayload({
    required this.sharedText,
    required this.urls,
    required this.images,
    required this.files,
  });

  final String sharedText;
  final List<Uri> urls;
  final List<ShareInboundImage> images;
  final List<ShareInboundFile> files;

  bool get hasText => sharedText.trim().isNotEmpty;

  bool get hasUrls => urls.isNotEmpty;

  bool get hasImages => images.isNotEmpty;

  /// Files that can be read as plain text and sent to AI as [AttachmentItem.textFile].
  List<ShareInboundFile> get textFiles =>
      files.where((f) => f.kind == ShareInboundFileKind.text).toList();

  /// Office docx files that will be converted to text and then sent as textFile.
  List<ShareInboundFile> get docxFiles =>
      files.where((f) => f.kind == ShareInboundFileKind.docx).toList();

  /// Importable bookshelf files (epub/pdf/azw3/...).
  ///
  /// Note: we treat `.txt` as a text file for AI (per product decision), so it is
  /// excluded from bookshelf candidates here.
  List<ShareInboundFile> get bookshelfFiles =>
      files.where((f) => f.kind == ShareInboundFileKind.bookshelf).toList();

  List<ShareInboundFile> get otherFiles =>
      files.where((f) => f.kind == ShareInboundFileKind.other).toList();

  bool get hasAiContent =>
      hasText ||
      hasUrls ||
      hasImages ||
      textFiles.isNotEmpty ||
      docxFiles.isNotEmpty;

  bool get hasOnlyBookshelfFiles =>
      !hasAiContent && bookshelfFiles.isNotEmpty && otherFiles.isEmpty;
}

class ShareInboundImage {
  ShareInboundImage({required this.path, this.mimeType});

  final String path;
  final String? mimeType;
}

enum ShareInboundFileKind {
  text,
  docx,
  bookshelf,
  other,
}

class ShareInboundFile {
  ShareInboundFile({
    required this.path,
    required this.filename,
    required this.kind,
  });

  final String path;
  final String filename;
  final ShareInboundFileKind kind;

  String get extLower {
    final name = filename.trim();
    final idx = name.lastIndexOf('.');
    if (idx < 0) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  static ShareInboundFileKind classifyByFilename(String filename) {
    final name = filename.trim();
    final idx = name.lastIndexOf('.');
    final ext = (idx < 0) ? '' : name.substring(idx + 1).toLowerCase();

    // Product decision: txt defaults to AI as a text attachment, not bookshelf import.
    const textExts = <String>{'txt', 'md', 'log', 'json', 'csv'};
    if (textExts.contains(ext)) return ShareInboundFileKind.text;

    if (ext == 'docx') return ShareInboundFileKind.docx;

    if (kAllowBookExtensions.contains(ext) && ext != 'txt') {
      return ShareInboundFileKind.bookshelf;
    }

    return ShareInboundFileKind.other;
  }
}

enum SharePanelMode {
  auto,
  aiChat,
  bookshelf,
  ask,
}

enum ShareDestination {
  aiChat,
  bookshelf,
  askUser,
}

class ShareDecision {
  ShareDecision._({
    required this.destination,
    this.bookshelfImportFiles = const [],
    this.bookshelfFileCards = const [],
  });

  final ShareDestination destination;

  /// Absolute file paths to be imported to bookshelf.
  final List<String> bookshelfImportFiles;

  /// Files to show in the AI UI as "import to bookshelf" cards.
  ///
  /// Used by policy B (mixed share): do NOT auto-import, just show buttons.
  final List<ShareInboundFile> bookshelfFileCards;

  factory ShareDecision.aiChat({
    List<ShareInboundFile> bookshelfFileCards = const [],
  }) {
    return ShareDecision._(
      destination: ShareDestination.aiChat,
      bookshelfFileCards: bookshelfFileCards,
    );
  }

  factory ShareDecision.bookshelf({
    required List<String> importFiles,
  }) {
    return ShareDecision._(
      destination: ShareDestination.bookshelf,
      bookshelfImportFiles: importFiles,
    );
  }

  factory ShareDecision.askUser() {
    return ShareDecision._(destination: ShareDestination.askUser);
  }
}
