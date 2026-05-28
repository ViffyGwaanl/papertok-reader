import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';

void main() {
  test('builds reader intent from source ref book anchor', () {
    final sourceRef = SourceRef(
      bookId: 7,
      href: 'Text/ch.xhtml',
      cfi: 'epubcfi(/6/4)',
      sourceKind: SourceRefKind.highlight,
    );

    final intent = PaperReaderReaderIntent.fromSourceRef(sourceRef);

    expect(intent, isNotNull);
    expect(intent!.bookId, 7);
    expect(intent.href, 'Text/ch.xhtml');
    expect(intent.cfi, 'epubcfi(/6/4)');
    expect(intent.toUri().toString(), contains('paperreader://reader/open?'));
  });

  test('parses source ref jump link before falling back to anchors', () {
    final sourceRef = SourceRef(
      bookId: 7,
      href: 'Text/ch.xhtml',
      jumpLink: 'paperreader://reader/open?bookId=8&href=Text%2Fother.xhtml',
      sourceKind: SourceRefKind.libraryRag,
    );

    final intent = PaperReaderReaderIntent.fromSourceRef(sourceRef);

    expect(intent!.bookId, 8);
    expect(intent.href, 'Text/other.xhtml');
  });

  test('audits jumpable unavailable and unresolved source refs', () {
    final audit = PaperReaderSourceJumpAudit.fromSourceRefs([
      SourceRef(
        bookId: 1,
        cfi: 'epubcfi(/6/2)',
        sourceKind: SourceRefKind.reader,
      ),
      SourceRef(
        unavailableReason: 'source book deleted',
        sourceKind: SourceRefKind.libraryRag,
      ),
      SourceRef(
        sourceTextSnippet: 'Hash-only text',
        sourceKind: SourceRefKind.external,
      ),
    ]);

    expect(audit.jumpableCount, 1);
    expect(audit.unavailableCount, 1);
    expect(audit.unresolvedIndexes, [2]);
    expect(audit.allResolved, false);
  });

  test('rejects malformed or non-reader source jump links', () {
    final malformed = SourceRef(
      jumpLink: 'not a uri',
      sourceKind: SourceRefKind.external,
    );
    final wrongHost = SourceRef(
      jumpLink: 'paperreader://library/open?bookId=1',
      sourceKind: SourceRefKind.external,
    );
    final noTarget = SourceRef(
      jumpLink: 'paperreader://reader/open?bookId=1',
      sourceKind: SourceRefKind.external,
    );

    expect(PaperReaderReaderIntent.fromSourceRef(malformed), isNull);
    expect(PaperReaderReaderIntent.fromSourceRef(wrongHost), isNull);
    expect(PaperReaderReaderIntent.fromSourceRef(noTarget), isNull);
  });
}
