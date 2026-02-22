import 'dart:io';
import 'dart:typed_data';

/// Allowed book extensions for import (lowercase, without leading dot).
///
/// Note: this is a UI/UX affordance. Real validation should still happen in
/// import processing.
const List<String> kAllowBookExtensions = <String>[
  'epub',
  'mobi',
  'azw3',
  'fb2',
  'txt',
  'pdf',
];

/// Returns `null` if the file looks valid for its extension.
/// Returns a human-readable error string if the signature is invalid.
///
/// Phase A implementation: validate only the most common/high-risk types.
Future<String?> validateBookMagicBytes(File file) async {
  final ext = _extensionLower(file.path);

  // Only validate where we have a stable, low-false-positive signature.
  if (ext == 'epub') {
    final header = await _readHeader(file, 4);
    final isZip = header.length >= 4 &&
        header[0] == 0x50 && // P
        header[1] == 0x4B && // K
        header[2] == 0x03 &&
        header[3] == 0x04;
    if (!isZip) {
      return 'Invalid EPUB file: ZIP signature not found.';
    }
  }

  if (ext == 'pdf') {
    final header = await _readHeader(file, 4);
    final isPdf = header.length >= 4 &&
        header[0] == 0x25 && // %
        header[1] == 0x50 && // P
        header[2] == 0x44 && // D
        header[3] == 0x46; // F
    if (!isPdf) {
      return 'Invalid PDF file: %PDF signature not found.';
    }
  }

  // txt/mobi/azw3/fb2: skipped (either no stable magic bytes or requires deeper parsing).
  return null;
}

String _extensionLower(String path) {
  final idx = path.lastIndexOf('.');
  if (idx < 0 || idx == path.length - 1) return '';
  return path.substring(idx + 1).toLowerCase();
}

Future<Uint8List> _readHeader(File file, int length) async {
  try {
    final raf = await file.open();
    try {
      final bytes = await raf.read(length);
      return Uint8List.fromList(bytes);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return Uint8List(0);
  }
}
