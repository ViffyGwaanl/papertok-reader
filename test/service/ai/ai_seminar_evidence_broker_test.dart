import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/ai_seminar_evidence_broker.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

void main() {
  SourceRef currentRef() => SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        sourceTextSnippet: 'Current book passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  SourceRef libraryRef() => SourceRef(
        bookId: 8,
        href: 'Text/other.xhtml',
        sourceTextSnippet: 'Library passage.',
        sourceKind: SourceRefKind.libraryRag,
      );

  test('uses current book evidence and does not call library by default',
      () async {
    var libraryCalls = 0;
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (_) async => AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [
          AiSemanticSearchEvidence(
            text: 'Current book passage.',
            href: 'Text/ch.xhtml',
            anchor: 'Chapter',
            jumpLink: 'paperreader://reader/open?bookId=7',
            score: 0.9,
            sourceRef: currentRef(),
          ),
        ],
      ),
      librarySearch: (_) async {
        libraryCalls += 1;
        return const AiSemanticSearchLibraryResult(
          ok: true,
          query: 'argument',
          evidence: [],
        );
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's1',
        question: 'argument',
        bookId: 7,
      ),
    );

    expect(libraryCalls, 0);
    expect(bundle.allEvidenceTraceable, true);
    expect(bundle.evidence.single.scope, AiSeminarEvidenceScope.currentBook);
    expect(bundle.evidence.single.sourceRef.sourceKind,
        SourceRefKind.currentBookRag);
  });

  test('seeds evidence from reader selection source refs', () async {
    var currentBookCalls = 0;
    var libraryCalls = 0;
    final selectionRef = SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/4)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/4%29',
      sourceTextSnippet: 'Selected passage text.',
      sourceKind: SourceRefKind.reader,
    );
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (_) async {
        currentBookCalls += 1;
        return const AiSemanticSearchResult(
          ok: true,
          bookId: 7,
          query: 'argument',
          evidence: [],
        );
      },
      librarySearch: (_) async {
        libraryCalls += 1;
        return const AiSemanticSearchLibraryResult(
          ok: true,
          query: 'argument',
          evidence: [],
        );
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's-selection',
        question: 'argument',
        bookId: 7,
        sourceRefs: [selectionRef],
      ),
    );

    expect(currentBookCalls, 1);
    expect(libraryCalls, 0);
    expect(bundle.evidence, hasLength(1));
    expect(bundle.evidence.single.id, 'selection-1');
    expect(bundle.evidence.single.text, 'Selected passage text.');
    expect(bundle.evidence.single.scope, AiSeminarEvidenceScope.currentBook);
    expect(bundle.evidence.single.sourceRef.sourceKind, SourceRefKind.reader);
    expect(bundle.evidence.single.sourceRef.cfi, 'epubcfi(/6/4)');
    expect(bundle.allEvidenceTraceable, true);
  });

  test('does not use the question as reader selection evidence text', () async {
    var libraryCalls = 0;
    final anchorOnlyRef = SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/4)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/4%29',
      sourceKind: SourceRefKind.reader,
    );
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (_) async => const AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [],
      ),
      librarySearch: (_) async {
        libraryCalls += 1;
        return const AiSemanticSearchLibraryResult(
          ok: true,
          query: 'argument',
          evidence: [],
        );
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's-selection-anchor-only',
        question: 'argument',
        bookId: 7,
        sourceRefs: [anchorOnlyRef],
      ),
    );

    expect(bundle.evidence, isEmpty);
    expect(libraryCalls, 1);
  });

  test('falls back to library when current book evidence is thin', () async {
    var libraryCalls = 0;
    final broker = AiSeminarEvidenceBroker(
      minCurrentBookEvidence: 2,
      currentBookSearch: (_) async => AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [
          AiSemanticSearchEvidence(
            text: 'Current book passage.',
            href: 'Text/ch.xhtml',
            anchor: 'Chapter',
            jumpLink: 'paperreader://reader/open?bookId=7',
            score: 0.9,
            sourceRef: currentRef(),
          ),
        ],
      ),
      librarySearch: (_) async {
        libraryCalls += 1;
        return AiSemanticSearchLibraryResult(
          ok: true,
          query: 'argument',
          evidence: [
            AiSemanticSearchLibraryEvidence(
              bookId: 8,
              bookTitle: 'Other',
              href: 'Text/other.xhtml',
              anchor: 'Other chapter',
              snippet: 'Library passage.',
              jumpLink: 'paperreader://reader/open?bookId=8',
              score: 0.8,
              sourceRef: libraryRef(),
            ),
          ],
        );
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's2',
        question: 'argument',
        bookId: 7,
      ),
    );

    expect(libraryCalls, 1);
    expect(bundle.evidence.map((e) => e.scope), [
      AiSeminarEvidenceScope.currentBook,
      AiSeminarEvidenceScope.library,
    ]);
  });

  test('uses library when session explicitly requests library scope', () async {
    var libraryCalls = 0;
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (_) async => const AiSemanticSearchResult(
        ok: false,
        bookId: 7,
        query: 'argument',
        evidence: [],
      ),
      librarySearch: (_) async {
        libraryCalls += 1;
        return AiSemanticSearchLibraryResult(
          ok: true,
          query: 'argument',
          evidence: [
            AiSemanticSearchLibraryEvidence(
              bookId: 8,
              bookTitle: 'Other',
              href: 'Text/other.xhtml',
              anchor: 'Other chapter',
              snippet: 'Library passage.',
              jumpLink: 'paperreader://reader/open?bookId=8',
              score: 0.8,
              sourceRef: libraryRef(),
            ),
          ],
        );
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's3',
        question: 'argument',
        bookId: 7,
        scopes: const [
          AiSeminarEvidenceScope.currentBook,
          AiSeminarEvidenceScope.library,
        ],
      ),
    );

    expect(libraryCalls, 1);
    expect(bundle.evidence.single.scope, AiSeminarEvidenceScope.library);
  });

  test('drops hash-only search results from the formal evidence bundle',
      () async {
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (_) async => AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [
          AiSemanticSearchEvidence(
            text: 'Detached text.',
            href: '',
            anchor: '',
            jumpLink: '',
            score: 0.1,
            sourceRef: SourceRef(
              sourceTextSnippet: 'Detached text.',
              sourceKind: SourceRefKind.external,
            ),
          ),
        ],
      ),
      librarySearch: (_) async => const AiSemanticSearchLibraryResult(
        ok: true,
        query: 'argument',
        evidence: [],
      ),
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(id: 's4', question: 'argument', bookId: 7),
    );

    expect(bundle.evidence, isEmpty);
  });
}
