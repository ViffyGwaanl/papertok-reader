import 'package:anx_reader/service/rag/ai_text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiTextChunker splits long text with overlap and respects maxChars', () {
    const chunker = AiTextChunker();

    final text = List.generate(
      40,
      (i) => 'Paragraph $i: ' + ('x' * 60),
    ).join('\n\n');

    final chunks = chunker.chunk(
      text,
      targetChars: 200,
      maxChars: 240,
      minChars: 120,
      overlapChars: 50,
    );

    expect(chunks.length, greaterThan(3));

    for (final c in chunks) {
      expect(c.text.length, lessThanOrEqualTo(240));
      expect(c.startChar, lessThan(c.endChar));
    }

    // Overlap: next chunk starts before previous ends.
    expect(chunks[1].startChar, lessThan(chunks[0].endChar));
  });
}
