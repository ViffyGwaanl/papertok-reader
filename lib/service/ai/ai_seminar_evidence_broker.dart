import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

typedef AiSeminarCurrentBookSearch = Future<AiSemanticSearchResult> Function(
  AiSeminarSessionContract session,
);

typedef AiSeminarLibrarySearch = Future<AiSemanticSearchLibraryResult> Function(
  AiSeminarSessionContract session,
);

typedef AiSeminarScopedEvidenceSearch = Future<List<AiSeminarEvidence>>
    Function(
  AiSeminarSessionContract session,
);

class AiSeminarEvidenceBroker {
  const AiSeminarEvidenceBroker({
    required AiSeminarCurrentBookSearch currentBookSearch,
    required AiSeminarLibrarySearch librarySearch,
    AiSeminarScopedEvidenceSearch? notesSearch,
    AiSeminarScopedEvidenceSearch? memorySearch,
    AiSeminarScopedEvidenceSearch? conceptGraphSearch,
    this.minCurrentBookEvidence = 1,
  })  : _currentBookSearch = currentBookSearch,
        _librarySearch = librarySearch,
        _notesSearch = notesSearch,
        _memorySearch = memorySearch,
        _conceptGraphSearch = conceptGraphSearch;

  final AiSeminarCurrentBookSearch _currentBookSearch;
  final AiSeminarLibrarySearch _librarySearch;
  final AiSeminarScopedEvidenceSearch? _notesSearch;
  final AiSeminarScopedEvidenceSearch? _memorySearch;
  final AiSeminarScopedEvidenceSearch? _conceptGraphSearch;
  final int minCurrentBookEvidence;

  Future<AiSeminarEvidenceBundle> fetch(
    AiSeminarSessionContract session,
  ) async {
    final evidence = <AiSeminarEvidence>[];
    evidence.addAll(_fromSessionSourceRefs(session));

    if (_shouldSearchCurrentBook(session)) {
      final current = await _currentBookSearch(session);
      evidence.addAll(_fromCurrentBook(current));
    }

    final currentCount = evidence
        .where((item) => item.scope == AiSeminarEvidenceScope.currentBook)
        .length;
    final needsLibrary = session.canUseLibrary ||
        currentCount < minCurrentBookEvidence ||
        !_shouldSearchCurrentBook(session);

    if (needsLibrary) {
      final library = await _librarySearch(session);
      evidence.addAll(_fromLibrary(library, offset: evidence.length));
    }

    await _appendScopedEvidence(
      evidence,
      session,
      AiSeminarEvidenceScope.notes,
      _notesSearch,
    );
    await _appendScopedEvidence(
      evidence,
      session,
      AiSeminarEvidenceScope.memory,
      _memorySearch,
    );
    await _appendScopedEvidence(
      evidence,
      session,
      AiSeminarEvidenceScope.conceptGraph,
      _conceptGraphSearch,
    );

    return AiSeminarEvidenceBundle(
      query: session.question,
      evidence: List.unmodifiable(evidence),
    );
  }

  bool _shouldSearchCurrentBook(AiSeminarSessionContract session) {
    return session.bookId != null &&
        (session.scopes.contains(AiSeminarEvidenceScope.currentBook) ||
            session.scopes.contains(AiSeminarEvidenceScope.currentChapter));
  }

  static Future<void> _appendScopedEvidence(
    List<AiSeminarEvidence> evidence,
    AiSeminarSessionContract session,
    AiSeminarEvidenceScope scope,
    AiSeminarScopedEvidenceSearch? search,
  ) async {
    if (search == null || !session.scopes.contains(scope)) return;
    final results = await search(session);
    for (final item in results) {
      if (item.scope != scope || !item.isTraceable) continue;
      evidence.add(item);
    }
  }

  static List<AiSeminarEvidence> _fromSessionSourceRefs(
    AiSeminarSessionContract session,
  ) {
    final out = <AiSeminarEvidence>[];
    for (final ref in session.sourceRefs) {
      if (!ref.hasEvidence) continue;
      final text = ref.sourceTextSnippet?.trim();
      if (text == null || text.isEmpty) continue;
      out.add(
        AiSeminarEvidence(
          id: 'selection-${out.length + 1}',
          scope: AiSeminarEvidenceScope.currentBook,
          text: text,
          sourceRef: ref,
          relevance: 1,
          note: 'Reader selection',
        ),
      );
    }
    return out;
  }

  static List<AiSeminarEvidence> _fromCurrentBook(
    AiSemanticSearchResult result,
  ) {
    if (!result.ok) return const <AiSeminarEvidence>[];
    final out = <AiSeminarEvidence>[];
    for (final item in result.evidence) {
      final sourceRef = item.sourceRef;
      if (sourceRef == null || !sourceRef.hasEvidence) continue;
      out.add(
        AiSeminarEvidence(
          id: 'current-${out.length + 1}',
          scope: AiSeminarEvidenceScope.currentBook,
          text: item.text,
          sourceRef: sourceRef,
          relevance: item.score,
        ),
      );
    }
    return out;
  }

  static List<AiSeminarEvidence> _fromLibrary(
    AiSemanticSearchLibraryResult result, {
    required int offset,
  }) {
    if (!result.ok) return const <AiSeminarEvidence>[];
    final out = <AiSeminarEvidence>[];
    for (final item in result.evidence) {
      final sourceRef = item.sourceRef;
      if (sourceRef == null || !sourceRef.hasEvidence) continue;
      out.add(
        AiSeminarEvidence(
          id: 'library-${offset + out.length + 1}',
          scope: AiSeminarEvidenceScope.library,
          text: item.snippet,
          sourceRef: sourceRef,
          relevance: item.score,
        ),
      );
    }
    return out;
  }
}
