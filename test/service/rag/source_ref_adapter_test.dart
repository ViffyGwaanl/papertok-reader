import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/rag/source_ref_adapter.dart';

void main() {
  test('library adapter produces safe source refs from RAG evidence', () {
    final ref = RagSourceRefAdapter.library(
      bookId: 12,
      href: 'Text/library.xhtml',
      snippet: List.filled(650, 'x').join(),
      bookTitle: 'Library Book',
      anchor: 'Chapter A',
      chunkId: 456,
      providerId: 'provider',
      model: 'embedding-model',
      indexVersion: 8,
      contextVersion: 2,
      confidence: 0.82,
    );

    expect(ref.bookId, 12);
    expect(ref.href, 'Text/library.xhtml');
    expect(ref.chunkId, 456);
    expect(ref.sourceKind, SourceRefKind.libraryRag);
    expect(ref.sourceTitle, 'Library Book');
    expect(ref.locationLabel, 'Chapter A');
    expect(ref.modelId, 'provider/embedding-model');
    expect(ref.algorithmVersion, 'library-rag-v1/index-v8/context-v2');
    expect(ref.confidence, 0.82);
    expect(ref.sourceTextSnippet!.length, lessThanOrEqualTo(500));

    final json = ref.toSafeJson();
    expect(json['jumpLink'], startsWith('paperreader://reader/open?'));
    expect(json['derivedCacheHint'], true);
    expect(json, isNot(contains('rawText')));
    expect(json, isNot(contains('contextText')));
    expect(json, isNot(contains('fullText')));
  });

  test('current book adapter reuses reader deep link scheme', () {
    final ref = RagSourceRefAdapter.currentBook(
      bookId: 5,
      href: 'Text/current.xhtml',
      text: 'current book evidence',
      anchor: 'Current Chapter',
      providerId: '',
      model: 'embedding-model',
      indexVersion: 1,
      confidence: 0.9,
    );

    expect(ref.sourceKind, SourceRefKind.currentBookRag);
    expect(ref.modelId, 'embedding-model');
    expect(ref.jumpLink, isNotNull);
    final uri = Uri.parse(ref.jumpLink!);
    expect(uri.scheme, 'paperreader');
    expect(uri.host, 'reader');
    expect(uri.path, '/open');
    expect(uri.queryParameters['bookId'], '5');
    expect(uri.queryParameters['href'], 'Text/current.xhtml');
  });
}
