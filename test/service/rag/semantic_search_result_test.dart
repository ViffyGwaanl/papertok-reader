import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/source_ref_adapter.dart';

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

  test('AiSemanticSearchResult serializes optional sourceRef safely', () {
    final sourceRef = RagSourceRefAdapter.currentBook(
      bookId: 1,
      href: 'Text/ch1.xhtml',
      text: 'snippet',
      jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch1.xhtml',
      chunkId: 9,
      model: 'test-model',
      indexVersion: 1,
    );
    final result = AiSemanticSearchResult(
      ok: true,
      bookId: 1,
      query: 'test',
      evidence: [
        AiSemanticSearchEvidence(
          text: 'snippet',
          href: 'Text/ch1.xhtml',
          anchor: 'Chapter 1',
          jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch1.xhtml',
          score: 0.9,
          sourceRef: sourceRef,
        ),
      ],
    );

    final json = result.toJson();
    final evidence = (json['evidence'] as List).cast<Map<String, dynamic>>();
    final sourceRefJson =
        Map<String, dynamic>.from(evidence.single['sourceRef'] as Map);
    expect(sourceRefJson, containsPair('bookId', 1));
    expect(sourceRefJson, containsPair('href', 'Text/ch1.xhtml'));
    expect(sourceRefJson, containsPair('chunkId', 9));
    expect(sourceRefJson, containsPair('derivedCacheHint', true));
    expect(sourceRefJson, contains('sourceHash'));
  });
}
