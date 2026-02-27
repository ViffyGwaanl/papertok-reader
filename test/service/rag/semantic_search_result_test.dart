import 'package:anx_reader/service/rag/semantic_search_current_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiSemanticSearchResult serializes evidence with required fields', () {
    final result = AiSemanticSearchResult(
      ok: true,
      bookId: 1,
      query: 'test',
      evidence: const [
        AiSemanticSearchEvidence(
          text: 'snippet',
          href: 'Text/ch1.xhtml',
          anchor: 'Chapter 1',
          jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch1.xhtml',
          score: 0.9,
        ),
      ],
    );

    final json = result.toJson();
    expect(json['ok'], true);
    expect(json['bookId'], 1);
    expect(json['query'], 'test');

    final evidence = (json['evidence'] as List).cast<Map<String, dynamic>>();
    expect(evidence, hasLength(1));
    expect(evidence.first, containsPair('text', 'snippet'));
    expect(evidence.first, containsPair('href', 'Text/ch1.xhtml'));
    expect(evidence.first, containsPair('anchor', 'Chapter 1'));
    expect(evidence.first, contains('jumpLink'));
    expect(evidence.first, contains('score'));
  });
}
