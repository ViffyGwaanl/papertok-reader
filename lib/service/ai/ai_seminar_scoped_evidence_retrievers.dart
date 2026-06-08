import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';

typedef AiSeminarNotesSearch = Future<List<NoteSearchResult>> Function({
  String? keyword,
  int? bookId,
  DateTime? from,
  DateTime? to,
  int limit,
});

typedef AiSeminarMemorySearch = Future<List<Map<String, dynamic>>> Function(
  String query, {
  int limit,
  bool includeLongTerm,
  bool includeDaily,
});

typedef AiSeminarConceptNodesLoader = Future<List<ConceptNode>> Function();
typedef AiSeminarConceptEdgesLoader = Future<List<ConceptEdge>> Function();

class AiSeminarScopedEvidenceRetrievers {
  const AiSeminarScopedEvidenceRetrievers({
    required AiSeminarNotesSearch notesSearch,
    required AiSeminarMemorySearch memorySearch,
    required AiSeminarConceptNodesLoader listConceptNodes,
    required AiSeminarConceptEdgesLoader listConceptEdges,
    this.limit = 6,
  })  : _notesSearch = notesSearch,
        _memorySearch = memorySearch,
        _listConceptNodes = listConceptNodes,
        _listConceptEdges = listConceptEdges;

  final AiSeminarNotesSearch _notesSearch;
  final AiSeminarMemorySearch _memorySearch;
  final AiSeminarConceptNodesLoader _listConceptNodes;
  final AiSeminarConceptEdgesLoader _listConceptEdges;
  final int limit;

  Future<List<AiSeminarEvidence>> notes(
    AiSeminarSessionContract session,
  ) async {
    final results = await _notesSearch(
      keyword: session.question,
      bookId: session.bookId,
      limit: limit,
    );
    final out = <AiSeminarEvidence>[];
    for (final result in results) {
      final text = _noteEvidenceText(result);
      if (text.isEmpty) continue;
      final sourceRef = BookNoteSourceRefAdapter.fromBookNote(
        result.note,
        sourceTitle: result.book.title,
      );
      if (!sourceRef.hasEvidence) continue;
      out.add(
        AiSeminarEvidence(
          id: 'notes-${result.note.id ?? out.length + 1}',
          scope: AiSeminarEvidenceScope.notes,
          text: text,
          sourceRef: sourceRef,
          note: result.book.title,
        ),
      );
      if (out.length >= limit) break;
    }
    return List.unmodifiable(out);
  }

  Future<List<AiSeminarEvidence>> memory(
    AiSeminarSessionContract session,
  ) async {
    final hits = await _memorySearch(
      session.question,
      limit: limit,
      includeLongTerm: true,
      includeDaily: true,
    );
    final out = <AiSeminarEvidence>[];
    for (final hit in hits) {
      final text = (hit['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final file = (hit['file'] ?? '').toString().trim();
      final line = (hit['line'] as num?)?.toInt();
      final label = [
        if (file.isNotEmpty) file,
        if (line != null) 'line $line',
      ].join(':');
      final sourceRef = SourceRef(
        sourceTitle: file.isEmpty ? 'Memory' : file,
        locationLabel: label.isEmpty ? null : label,
        sourceTextSnippet: text,
        sourceTextForHash: '$file|${line ?? ''}|$text',
        sourceKind: SourceRefKind.memory,
        unavailableReason: _memoryUnavailableReason(file, line),
      );
      if (!sourceRef.hasEvidence) continue;
      out.add(
        AiSeminarEvidence(
          id: 'memory-${out.length + 1}',
          scope: AiSeminarEvidenceScope.memory,
          text: text,
          sourceRef: sourceRef,
        ),
      );
      if (out.length >= limit) break;
    }
    return List.unmodifiable(out);
  }

  Future<List<AiSeminarEvidence>> conceptGraph(
    AiSeminarSessionContract session,
  ) async {
    final nodes = await _listConceptNodes();
    final edges = await _listConceptEdges();
    final nodeById = {for (final node in nodes) node.id: node};
    final out = <AiSeminarEvidence>[];

    for (final node in nodes) {
      if (out.length >= limit) break;
      if (!node.hasEvidence) continue;
      if (!_matchesQuery(session.question, [node.label, node.summary])) {
        continue;
      }
      final sourceRef = _firstTraceable(node.sourceRefs);
      if (sourceRef == null) continue;
      out.add(
        AiSeminarEvidence(
          id: 'concept-node-${node.id}',
          scope: AiSeminarEvidenceScope.conceptGraph,
          text: _joinText([node.label, node.summary]),
          sourceRef: sourceRef,
        ),
      );
    }

    for (final edge in edges) {
      if (out.length >= limit) break;
      if (!edge.hasEvidence) continue;
      final sourceLabel = nodeById[edge.sourceNodeId]?.label;
      final targetLabel = nodeById[edge.targetNodeId]?.label;
      if (!_matchesQuery(
        session.question,
        [
          edge.label,
          edge.type.asString,
          sourceLabel,
          targetLabel,
        ],
      )) {
        continue;
      }
      final sourceRef = _firstTraceable(edge.evidenceRefs);
      if (sourceRef == null) continue;
      out.add(
        AiSeminarEvidence(
          id: 'concept-edge-${edge.id}',
          scope: AiSeminarEvidenceScope.conceptGraph,
          text: _joinText([
            sourceLabel,
            edge.label ?? edge.type.asString,
            targetLabel,
          ]),
          sourceRef: sourceRef,
        ),
      );
    }

    return List.unmodifiable(out);
  }

  static String _noteEvidenceText(NoteSearchResult result) {
    final readerNote = result.note.readerNote?.trim();
    if (readerNote != null && readerNote.isNotEmpty) return readerNote;
    return result.note.content.trim();
  }

  static SourceRef? _firstTraceable(Iterable<SourceRef> refs) {
    for (final ref in refs) {
      if (ref.hasEvidence) return ref;
    }
    return null;
  }

  static String _memoryUnavailableReason(String file, int? line) {
    final pointer = [
      if (file.trim().isNotEmpty) file.trim(),
      if (line != null) 'line-$line',
    ].join(':');
    if (pointer.isEmpty) return 'memory-source-not-jumpable';
    return 'memory-source-not-jumpable:$pointer';
  }

  static bool _matchesQuery(String query, Iterable<String?> values) {
    final haystack = values
        .whereType<String>()
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (haystack.isEmpty) return false;
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    if (haystack.contains(normalizedQuery)) return true;
    final tokens = RegExp(r'[0-9a-zA-Z_]+|[\u4e00-\u9fff]+')
        .allMatches(normalizedQuery)
        .map((match) => match.group(0) ?? '')
        .where((token) => token.trim().length >= 2);
    for (final token in tokens) {
      if (haystack.contains(token)) return true;
    }
    return false;
  }

  static String _joinText(Iterable<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' - ');
  }
}
