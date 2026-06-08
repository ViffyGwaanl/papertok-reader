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

  SourceRef scopedRef({
    required SourceRefKind kind,
    required String text,
    String href = 'Text/ch.xhtml',
  }) =>
      SourceRef(
        bookId: 7,
        href: href,
        sourceTextSnippet: text,
        sourceKind: kind,
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

  test('uses notes memory and concept graph retrievers for enabled scopes',
      () async {
    final calls = <String>[];
    final broker = AiSeminarEvidenceBroker(
      minCurrentBookEvidence: 0,
      currentBookSearch: (_) async => const AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [],
      ),
      librarySearch: (_) async => const AiSemanticSearchLibraryResult(
        ok: true,
        query: 'argument',
        evidence: [],
      ),
      notesSearch: (_) async {
        calls.add('notes');
        return [
          AiSeminarEvidence(
            id: 'notes-1',
            scope: AiSeminarEvidenceScope.notes,
            text: 'Saved note passage.',
            sourceRef: scopedRef(
              kind: SourceRefKind.note,
              text: 'Saved note passage.',
            ),
          ),
        ];
      },
      memorySearch: (_) async {
        calls.add('memory');
        return [
          AiSeminarEvidence(
            id: 'memory-1',
            scope: AiSeminarEvidenceScope.memory,
            text: 'Applied memory passage.',
            sourceRef: scopedRef(
              kind: SourceRefKind.memory,
              text: 'Applied memory passage.',
            ),
          ),
        ];
      },
      conceptGraphSearch: (_) async {
        calls.add('conceptGraph');
        return [
          AiSeminarEvidence(
            id: 'concept-1',
            scope: AiSeminarEvidenceScope.conceptGraph,
            text: 'Concept node summary.',
            sourceRef: scopedRef(
              kind: SourceRefKind.currentBookRag,
              text: 'Concept node summary.',
            ),
          ),
        ];
      },
    );

    final bundle = await broker.fetch(
      AiSeminarSessionContract(
        id: 's-scoped',
        question: 'argument',
        bookId: 7,
        scopes: const [
          AiSeminarEvidenceScope.currentBook,
          AiSeminarEvidenceScope.notes,
          AiSeminarEvidenceScope.memory,
          AiSeminarEvidenceScope.conceptGraph,
        ],
      ),
    );

    expect(calls, ['notes', 'memory', 'conceptGraph']);
    expect(
      bundle.evidence.map((e) => e.scope),
      [
        AiSeminarEvidenceScope.notes,
        AiSeminarEvidenceScope.memory,
        AiSeminarEvidenceScope.conceptGraph,
      ],
    );
    expect(
      bundle.evidence.map((e) => e.sourceRef.sourceKind),
      [
        SourceRefKind.note,
        SourceRefKind.memory,
        SourceRefKind.currentBookRag,
      ],
    );
    expect(bundle.allEvidenceTraceable, true);
  });

  test('does not call scoped retrievers when their scopes are disabled',
      () async {
    var scopedCalls = 0;
    final broker = AiSeminarEvidenceBroker(
      minCurrentBookEvidence: 0,
      currentBookSearch: (_) async => const AiSemanticSearchResult(
        ok: true,
        bookId: 7,
        query: 'argument',
        evidence: [],
      ),
      librarySearch: (_) async => const AiSemanticSearchLibraryResult(
        ok: true,
        query: 'argument',
        evidence: [],
      ),
      notesSearch: (_) async {
        scopedCalls += 1;
        return const <AiSeminarEvidence>[];
      },
      memorySearch: (_) async {
        scopedCalls += 1;
        return const <AiSeminarEvidence>[];
      },
      conceptGraphSearch: (_) async {
        scopedCalls += 1;
        return const <AiSeminarEvidence>[];
      },
    );

    await broker.fetch(
      AiSeminarSessionContract(
        id: 's-no-scoped',
        question: 'argument',
        bookId: 7,
        scopes: const [AiSeminarEvidenceScope.currentBook],
      ),
    );

    expect(scopedCalls, 0);
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
