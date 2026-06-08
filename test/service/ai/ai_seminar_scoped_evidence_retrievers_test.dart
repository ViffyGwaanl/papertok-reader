import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/ai_seminar_scoped_evidence_retrievers.dart';
import 'package:papertok_reader/service/ai/tools/repository/notes_repository.dart';

void main() {
  test('maps notes memory and concept graph stores into traceable evidence',
      () async {
    String? requestedNoteKeyword;
    int? requestedNoteBookId;
    String? requestedMemoryQuery;
    final retrievers = AiSeminarScopedEvidenceRetrievers(
      notesSearch: ({
        String? keyword,
        int? bookId,
        DateTime? from,
        DateTime? to,
        int limit = 10,
      }) async {
        requestedNoteKeyword = keyword;
        requestedNoteBookId = bookId;
        return [
          NoteSearchResult(
            book: Book.mock().copyWith(id: 7, title: 'Graph Book'),
            note: BookNote(
              id: 42,
              bookId: 7,
              content: 'GraphRAG note highlight.',
              cfi: 'epubcfi(/6/8)',
              chapter: 'Chapter 2',
              type: 'note',
              color: 'ffff00',
              readerNote: 'GraphRAG reader note.',
              updateTime: DateTime.utc(2026, 6, 4),
            ),
          ),
        ];
      },
      memorySearch: (
        String query, {
        int limit = 20,
        bool includeLongTerm = true,
        bool includeDaily = true,
      }) async {
        requestedMemoryQuery = query;
        return [
          {
            'file': 'MEMORY.md',
            'line': 12,
            'text': 'Remember GraphRAG tradeoffs.',
          },
        ];
      },
      listConceptNodes: () async => [
        ConceptNode(
          id: 'graph-rag',
          type: ConceptNodeType.concept,
          label: 'GraphRAG',
          summary: 'Connects concepts through cited chunk evidence.',
          sourceRefs: [
            SourceRef(
              bookId: 7,
              href: 'Text/graph.xhtml',
              sourceTextSnippet: 'GraphRAG cited node evidence.',
              sourceKind: SourceRefKind.currentBookRag,
            ),
          ],
        ),
      ],
      listConceptEdges: () async => [
        ConceptEdge(
          id: 'graph-rag-supports-map',
          sourceNodeId: 'graph-rag',
          targetNodeId: 'understanding-map',
          type: ConceptEdgeType.supports,
          label: 'supports understanding map',
          evidenceRefs: [
            SourceRef(
              bookId: 7,
              href: 'Text/map.xhtml',
              sourceTextSnippet: 'Graph relation evidence.',
              sourceKind: SourceRefKind.currentBookRag,
            ),
          ],
        ),
      ],
    );

    final session = AiSeminarSessionContract(
      id: 's-scoped-real',
      question: 'GraphRAG',
      bookId: 7,
    );

    final notes = await retrievers.notes(session);
    final memory = await retrievers.memory(session);
    final graph = await retrievers.conceptGraph(session);

    expect(requestedNoteKeyword, 'GraphRAG');
    expect(requestedNoteBookId, 7);
    expect(requestedMemoryQuery, 'GraphRAG');
    expect(notes.single.scope, AiSeminarEvidenceScope.notes);
    expect(notes.single.sourceRef.sourceKind, SourceRefKind.note);
    expect(notes.single.sourceRef.canJumpBack, true);
    expect(memory.single.scope, AiSeminarEvidenceScope.memory);
    expect(memory.single.sourceRef.sourceKind, SourceRefKind.memory);
    expect(memory.single.sourceRef.hasUnavailableReason, true);
    expect(graph.map((e) => e.scope), [
      AiSeminarEvidenceScope.conceptGraph,
      AiSeminarEvidenceScope.conceptGraph,
    ]);
    expect(graph.every((e) => e.isTraceable), true);
  });
}
