/// Lightweight text statistics helpers.
///
/// We use this to (a) expose word/character counts to AI tools and (b)
/// implement the short-book full-context heuristic.
class TextStats {
  const TextStats({
    required this.characters,
    required this.nonWhitespaceCharacters,
    required this.estimatedWords,
  });

  /// Total UTF-16 code units (Dart's `String.length`).
  final int characters;

  /// Characters excluding whitespace.
  final int nonWhitespaceCharacters;

  /// Best-effort word count.
  ///
  /// - For CJK (Han/Hiragana/Katakana/Hangul), counts each ideograph/syllable.
  /// - For Latin text, counts contiguous `[A-Za-z0-9]` sequences.
  final int estimatedWords;

  static TextStats fromText(String text) {
    if (text.isEmpty) {
      return const TextStats(
        characters: 0,
        nonWhitespaceCharacters: 0,
        estimatedWords: 0,
      );
    }

    var nonWs = 0;
    var words = 0;
    var inAsciiWord = false;

    for (final rune in text.runes) {
      final isWhitespace = rune == 0x20 ||
          rune == 0x09 ||
          rune == 0x0A ||
          rune == 0x0D ||
          rune == 0x0C;

      if (!isWhitespace) {
        nonWs += 1;
      }

      if (_isCjkLike(rune)) {
        // Treat each ideograph/syllable as a word.
        words += 1;
        inAsciiWord = false;
        continue;
      }

      final isAsciiAlnum = (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);

      if (isAsciiAlnum) {
        if (!inAsciiWord) {
          words += 1;
          inAsciiWord = true;
        }
        continue;
      }

      // Any other separator/punctuation ends the ASCII word.
      inAsciiWord = false;
    }

    return TextStats(
      characters: text.length,
      nonWhitespaceCharacters: nonWs,
      estimatedWords: words,
    );
  }

  static bool _isCjkLike(int rune) {
    // Han ideographs
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF)) {
      return true;
    }

    // Hiragana / Katakana
    if ((rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF)) {
      return true;
    }

    // Hangul
    if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F)) {
      return true;
    }

    return false;
  }
}
