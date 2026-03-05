import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Output of DOCX -> plain text extraction.
class DocxPlainTextResult {
  DocxPlainTextResult({
    required this.text,
    required this.truncated,
  });

  final String text;
  final bool truncated;
}

/// Basic ZIP-bomb guardrails for untrusted DOCX files.
class DocxZipLimits {
  const DocxZipLimits({
    this.maxEntries = 2048,
    this.maxTotalUncompressedBytes = 40 * 1024 * 1024,
    this.maxCompressionRatio = 200.0,
  });

  /// Maximum number of ZIP entries.
  final int maxEntries;

  /// Maximum sum of uncompressed sizes across entries.
  final int maxTotalUncompressedBytes;

  /// Maximum allowed ratio: (uncompressed bytes / compressed bytes).
  ///
  /// This is a heuristic; it is checked per-entry.
  final double maxCompressionRatio;
}

/// Minimal DOCX (WordprocessingML) -> plain text extractor.
///
/// Constraints:
/// - Uses only the `archive` package to read the DOCX zip.
/// - Does not use an XML parser; it scans the XML string.
/// - Handles only a small subset of tags:
///   - `<w:t>` text runs
///   - `<w:tab/>` -> '\t'
///   - `<w:br/>` and `<w:cr/>` -> '\n'
///   - `</w:p>` -> paragraph break ('\n\n')
class DocxPlainTextExtractor {
  DocxPlainTextExtractor._();

  static const int defaultMaxChars = 200000;

  static DocxPlainTextResult extract(
    Uint8List docxBytes, {
    int maxChars = defaultMaxChars,
    DocxZipLimits zipLimits = const DocxZipLimits(),
  }) {
    if (maxChars <= 0) {
      return DocxPlainTextResult(text: '', truncated: true);
    }

    final archive = ZipDecoder().decodeBytes(docxBytes);

    _validateZip(archive, zipLimits);

    final docFile = _findWordDocumentXml(archive);
    if (docFile == null) {
      throw const FormatException('Invalid DOCX: missing word/document.xml');
    }

    // Decompress only after zip-level checks.
    final raw = docFile.content;
    if (raw is! List<int>) {
      throw const FormatException('Invalid DOCX: unreadable word/document.xml');
    }

    final xml = utf8.decode(raw, allowMalformed: true);
    return _wordXmlToPlainText(xml, maxChars: maxChars);
  }

  static ArchiveFile? _findWordDocumentXml(Archive archive) {
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      if (name == 'word/document.xml') {
        return f;
      }
    }
    // Fallback: tolerate strange leading paths.
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      if (name.endsWith('/word/document.xml')) {
        return f;
      }
    }
    return null;
  }

  static void _validateZip(Archive archive, DocxZipLimits limits) {
    final files = archive.files;
    if (files.length > limits.maxEntries) {
      throw FormatException(
        'DOCX rejected: too many zip entries (${files.length} > ${limits.maxEntries})',
      );
    }

    var totalUncompressed = 0;

    for (final f in files) {
      if (!f.isFile) continue;

      final uncompressed = f.size;
      if (uncompressed > 0) {
        totalUncompressed += uncompressed;
        if (totalUncompressed > limits.maxTotalUncompressedBytes) {
          throw FormatException(
            'DOCX rejected: uncompressed size too large ($totalUncompressed > ${limits.maxTotalUncompressedBytes})',
          );
        }
      }

      // Compression ratio heuristic (zip-bomb defense).
      final compressed = f.rawContent?.length ?? 0;
      if (compressed > 0 && uncompressed > 0) {
        final ratio = uncompressed / compressed;
        if (ratio > limits.maxCompressionRatio) {
          throw FormatException(
            'DOCX rejected: suspicious compression ratio (${ratio.toStringAsFixed(1)} > ${limits.maxCompressionRatio})',
          );
        }
      }
    }
  }

  static DocxPlainTextResult _wordXmlToPlainText(
    String xml, {
    required int maxChars,
  }) {
    final out = StringBuffer();
    var outLen = 0;
    var truncated = false;

    void append(String s) {
      if (s.isEmpty || truncated) return;
      final remaining = maxChars - outLen;
      if (remaining <= 0) {
        truncated = true;
        return;
      }
      if (s.length <= remaining) {
        out.write(s);
        outLen += s.length;
        return;
      }
      out.write(s.substring(0, remaining));
      outLen = maxChars;
      truncated = true;
    }

    var i = 0;
    while (i < xml.length && !truncated) {
      final lt = xml.indexOf('<', i);
      if (lt < 0) break;

      // Skip text between tags (WordprocessingML content we care about is in tags).
      i = lt;

      // Find end of tag.
      final gt = xml.indexOf('>', i + 1);
      if (gt < 0) break;

      // Tag snippet without the closing '>'
      final tag = xml.substring(i, gt);

      // Parse the tag name to avoid false positives like `<w:tbl>` matching `<w:t`.
      final isClosing = tag.startsWith('</');
      final name = _tagName(tag);
      if (name == null) {
        i = gt + 1;
        continue;
      }

      // Closing paragraph -> blank line.
      if (isClosing && name == 'w:p') {
        append('\n\n');
        i = gt + 1;
        continue;
      }

      // Inline breaks.
      if (!isClosing && (name == 'w:br' || name == 'w:cr')) {
        append('\n');
        i = gt + 1;
        continue;
      }

      // Tabs.
      if (!isClosing && name == 'w:tab') {
        append('\t');
        i = gt + 1;
        continue;
      }

      // Text runs.
      if (!isClosing && name == 'w:t') {
        // Ignore self-closing <w:t/>.
        if (tag.endsWith('/')) {
          i = gt + 1;
          continue;
        }

        final close = xml.indexOf('</w:t>', gt + 1);
        if (close < 0) {
          // Malformed XML; stop.
          break;
        }

        final inner = xml.substring(gt + 1, close);
        append(_xmlUnescape(inner));
        i = close + '</w:t>'.length;
        continue;
      }

      i = gt + 1;
    }

    var text = out.toString();

    // Normalize: collapse 3+ newlines to a single paragraph break.
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return DocxPlainTextResult(text: text, truncated: truncated);
  }

  static String? _tagName(String tag) {
    if (tag.isEmpty || !tag.startsWith('<')) return null;
    if (tag.startsWith('<!--') ||
        tag.startsWith('<?') ||
        tag.startsWith('<!')) {
      return null;
    }

    final isClosing = tag.startsWith('</');
    final start = isClosing ? 2 : 1;
    if (start >= tag.length) return null;

    var end = start;
    while (end < tag.length) {
      final c = tag.codeUnitAt(end);
      // Space, tab, CR/LF, or self-closing slash.
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2F) {
        break;
      }
      end++;
    }

    if (end <= start) return null;
    return tag.substring(start, end);
  }

  static String _xmlUnescape(String s) {
    if (s.isEmpty || !s.contains('&')) return s;

    final out = StringBuffer();
    var i = 0;

    while (i < s.length) {
      final amp = s.indexOf('&', i);
      if (amp < 0) {
        out.write(s.substring(i));
        break;
      }

      if (amp > i) {
        out.write(s.substring(i, amp));
      }

      final semi = s.indexOf(';', amp + 1);
      if (semi < 0) {
        // No terminator; keep as-is.
        out.write('&');
        i = amp + 1;
        continue;
      }

      final entity = s.substring(amp + 1, semi);
      final decoded = _decodeEntity(entity);
      if (decoded != null) {
        out.write(decoded);
      } else {
        out.write('&');
        out.write(entity);
        out.write(';');
      }

      i = semi + 1;
    }

    return out.toString();
  }

  static String? _decodeEntity(String entity) {
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }

    if (entity.startsWith('#')) {
      final raw = entity.substring(1);
      final isHex = raw.startsWith('x') || raw.startsWith('X');
      final digits = isHex ? raw.substring(1) : raw;
      if (digits.isEmpty) return null;

      final value = int.tryParse(digits, radix: isHex ? 16 : 10);
      if (value == null || value < 0 || value > 0x10FFFF) return null;
      return String.fromCharCode(value);
    }

    return null;
  }
}
