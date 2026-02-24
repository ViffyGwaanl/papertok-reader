import 'dart:math';

/// A text chunk extracted from a larger source string.
class AiTextChunk {
  const AiTextChunk({
    required this.text,
    required this.startChar,
    required this.endChar,
  });

  final String text;

  /// Start character offset in the original source string.
  final int startChar;

  /// End character offset (exclusive) in the original source string.
  final int endChar;

  int get length => text.length;
}

/// A simple sliding-window chunker for RAG indexing.
///
/// - Character-based for deterministic behavior across languages.
/// - Produces overlaps to preserve context at chunk boundaries.
class AiTextChunker {
  const AiTextChunker();

  static const int defaultTargetChars = 900;
  static const int defaultMaxChars = 1200;
  static const int defaultMinChars = 200;
  static const int defaultOverlapChars = 150;

  List<AiTextChunk> chunk(
    String raw, {
    int targetChars = defaultTargetChars,
    int maxChars = defaultMaxChars,
    int minChars = defaultMinChars,
    int overlapChars = defaultOverlapChars,
  }) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const [];

    final t = targetChars.clamp(200, 4000);
    final mx = maxChars.clamp(t, 6000);
    final mn = minChars.clamp(50, t);
    final ov = overlapChars.clamp(0, t - 1);

    final chunks = <AiTextChunk>[];

    int i = 0;
    while (i < text.length) {
      // Force forward progress.
      i = i.clamp(0, text.length);
      if (i >= text.length) break;

      final remaining = text.length - i;
      if (remaining <= mx) {
        final tail = text.substring(i).trim();
        if (tail.isNotEmpty) {
          chunks.add(
            AiTextChunk(text: tail, startChar: i, endChar: text.length),
          );
        }
        break;
      }

      final ideal = min(i + t, text.length);
      final maxEnd = min(i + mx, text.length);
      final minEnd = min(i + mn, text.length);

      // Prefer breaking at a natural boundary near `ideal`.
      var end = _findBreakForward(text, ideal, maxEnd);
      if (end < minEnd) {
        end = _findBreakBackward(text, ideal, minEnd);
      }

      // Fallback: hard cut.
      end = end.clamp(minEnd, maxEnd);

      final slice = text.substring(i, end).trim();
      if (slice.isNotEmpty) {
        chunks.add(AiTextChunk(text: slice, startChar: i, endChar: end));
      }

      // Next window start with overlap.
      final next = end - ov;
      if (next <= i) {
        // Should never happen, but guard against infinite loops.
        i = end;
      } else {
        i = next;
      }
    }

    // De-duplicate accidental identical chunks (can happen with heavy trimming).
    final seen = <String>{};
    final filtered = <AiTextChunk>[];
    for (final c in chunks) {
      final key = '${c.startChar}:${c.endChar}:${c.text}';
      if (seen.add(key)) filtered.add(c);
    }

    return filtered;
  }

  int _findBreakForward(String text, int from, int to) {
    for (var j = from; j < to; j++) {
      final ch = text.codeUnitAt(j);
      if (_isBoundary(ch)) {
        return j;
      }
    }
    return from;
  }

  int _findBreakBackward(String text, int from, int minEnd) {
    for (var j = from; j > minEnd; j--) {
      final ch = text.codeUnitAt(j - 1);
      if (_isBoundary(ch)) {
        return j;
      }
    }
    return minEnd;
  }

  bool _isBoundary(int ch) {
    // whitespace
    if (ch == 0x20 || ch == 0x09 || ch == 0x0A) return true;

    // punctuation boundaries
    const boundaries = <int>{
      0x2E, // .
      0x3F, // ?
      0x21, // !
      0x3B, // ;
      0x3A, // :
      0x2C, // ,
      0x3002, // 。
      0xFF1F, // ？
      0xFF01, // ！
      0xFF1B, // ；
      0xFF1A, // ：
      0xFF0C, // ，
      0x2026, // …
    };
    return boundaries.contains(ch);
  }
}
