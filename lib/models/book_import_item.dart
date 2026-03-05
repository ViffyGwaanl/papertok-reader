import 'dart:io';

import 'package:meta/meta.dart';

/// UI-only book import item for AI chat.
///
/// This is intentionally *not* an AI attachment: we never send the book bytes to
/// the model. It only exists to let users import shared/picked book files into
/// the bookshelf from within the chat UI.
@immutable
class BookImportItem {
  const BookImportItem({
    required this.file,
    required this.filename,
  });

  final File file;
  final String filename;

  String get extension {
    final name = filename;
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }
}
