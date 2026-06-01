import 'dart:collection';

import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';

abstract class DerivedBookConceptGraphLoader {
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  });
}

class DerivedBookConceptGraphSnapshot {
  const DerivedBookConceptGraphSnapshot({
    required this.bookId,
    this.nodes = const <ConceptNode>[],
    this.edges = const <ConceptEdge>[],
  });

  factory DerivedBookConceptGraphSnapshot.empty(int bookId) {
    return DerivedBookConceptGraphSnapshot(bookId: bookId);
  }

  final int bookId;
  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;

  bool get isEmpty => nodes.isEmpty;
}

class AiGlobalDerivedBookConceptGraphLoader
    implements DerivedBookConceptGraphLoader {
  AiGlobalDerivedBookConceptGraphLoader({AiIndexDatabase? database})
      : _database = database ?? AiIndexDatabase.instance;

  final AiIndexDatabase _database;

  static const String algorithmVersion = 'graphrag-global-layer-v1';

  @override
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  }) async {
    if (bookId <= 0) return DerivedBookConceptGraphSnapshot.empty(bookId);
    final db = await _database.database;
    if (!await _tableExists('ai_graph_nodes') ||
        !await _tableExists('ai_graph_edges') ||
        !await _tableExists('ai_graph_node_chunks') ||
        !await _tableExists('ai_chunks')) {
      return DerivedBookConceptGraphSnapshot.empty(bookId);
    }

    final safeLimit = nodeLimit.clamp(2, 60).toInt();
    final nodeRows = await db.rawQuery(
      '''
SELECT
  gn.id AS node_id,
  gn.name AS name,
  gn.summary AS summary,
  gn.confidence AS confidence,
  gn.created_at AS created_at,
  gn.updated_at AS updated_at,
  c.id AS chunk_id,
  c.chapter_href AS chapter_href,
  c.chapter_title AS chapter_title,
  c.chunk_index AS chunk_index,
  COALESCE(NULLIF(c.raw_text, ''), c.text) AS snippet
FROM (
  SELECT id, name, summary, confidence, created_at, updated_at
  FROM ai_graph_nodes
  WHERE book_id = ?
  ORDER BY COALESCE(confidence, 0) DESC, id ASC
  LIMIT ?
) gn
LEFT JOIN ai_graph_node_chunks gnc ON gnc.node_id = gn.id
LEFT JOIN ai_chunks c ON c.id = gnc.chunk_id
ORDER BY COALESCE(gn.confidence, 0) DESC, gn.id ASC, c.id ASC
''',
      [bookId, safeLimit],
    );

    final builders = LinkedHashMap<int, _DerivedNodeBuilder>();
    for (final row in nodeRows) {
      final nodeId = (row['node_id'] as num?)?.toInt();
      if (nodeId == null) continue;
      final builder = builders.putIfAbsent(
        nodeId,
        () => _DerivedNodeBuilder(
          dbId: nodeId,
          bookId: bookId,
          name: (row['name']?.toString() ?? '').trim(),
          summary: (row['summary']?.toString() ?? '').trim(),
          confidence: (row['confidence'] as num?)?.toDouble(),
          createdAt: (row['created_at'] as num?)?.toInt(),
          updatedAt: (row['updated_at'] as num?)?.toInt(),
        ),
      );
      final ref = _sourceRefFromRow(bookId, row, builder.confidence);
      if (ref != null && builder.sourceRefs.length < 4) {
        builder.sourceRefs.add(ref);
      }
    }

    final groundedBuilders = builders.values
        .where((builder) => builder.sourceRefs.isNotEmpty)
        .toList(growable: false);
    final nodes = groundedBuilders
        .map((builder) => builder.toConceptNode())
        .toList(growable: false);
    if (nodes.isEmpty) {
      return DerivedBookConceptGraphSnapshot.empty(bookId);
    }

    final edges = await _loadEdges(
      bookId: bookId,
      dbIdToNodeId: {
        for (final builder in groundedBuilders) builder.dbId: builder.nodeId,
      },
      nodesById: {for (final node in nodes) node.id: node},
      limit: safeLimit * 3,
    );

    return DerivedBookConceptGraphSnapshot(
      bookId: bookId,
      nodes: nodes,
      edges: edges,
    );
  }

  Future<List<ConceptEdge>> _loadEdges({
    required int bookId,
    required Map<int, String> dbIdToNodeId,
    required Map<String, ConceptNode> nodesById,
    required int limit,
  }) async {
    if (dbIdToNodeId.isEmpty) return const <ConceptEdge>[];
    final db = await _database.database;
    final dbIds = dbIdToNodeId.keys.toList(growable: false);
    final placeholders = List.filled(dbIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
SELECT id, src_node_id, dst_node_id, relation, weight, evidence_count,
       created_at, updated_at
FROM ai_graph_edges
WHERE book_id = ?
  AND src_node_id IN ($placeholders)
  AND dst_node_id IN ($placeholders)
ORDER BY COALESCE(weight, 0) DESC, id ASC
LIMIT ?
''',
      [bookId, ...dbIds, ...dbIds, limit],
    );

    final edges = <ConceptEdge>[];
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      final srcDbId = (row['src_node_id'] as num?)?.toInt();
      final dstDbId = (row['dst_node_id'] as num?)?.toInt();
      if (id == null || srcDbId == null || dstDbId == null) continue;
      final sourceId = dbIdToNodeId[srcDbId];
      final targetId = dbIdToNodeId[dstDbId];
      if (sourceId == null || targetId == null) continue;
      final source = nodesById[sourceId];
      final target = nodesById[targetId];
      final relation = (row['relation']?.toString() ?? '').trim();
      final evidenceRefs = <SourceRef>[
        if (source != null) ...source.sourceRefs.take(1),
        if (target != null) ...target.sourceRefs.take(1),
      ];
      edges.add(
        ConceptEdge(
          id: 'derived:book:$bookId:graph-edge:$id',
          sourceNodeId: sourceId,
          targetNodeId: targetId,
          type: _edgeType(relation),
          label: relation.isEmpty ? 'co_occurs' : relation,
          evidenceRefs: evidenceRefs,
          confidence: (row['weight'] as num?)?.toDouble(),
          ownership: AiOutputOwnership.derivedCache,
          createdAt: (row['created_at'] as num?)?.toInt(),
          updatedAt: (row['updated_at'] as num?)?.toInt(),
        ),
      );
    }
    return edges;
  }

  Future<bool> _tableExists(String table) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual table') AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  SourceRef? _sourceRefFromRow(
    int bookId,
    Map<String, Object?> row,
    double? confidence,
  ) {
    final chunkId = (row['chunk_id'] as num?)?.toInt();
    final href = (row['chapter_href']?.toString() ?? '').trim();
    final snippet = (row['snippet']?.toString() ?? '').trim();
    if (chunkId == null && href.isEmpty && snippet.isEmpty) return null;
    final chapterTitle = (row['chapter_title']?.toString() ?? '').trim();
    final chunkIndex = (row['chunk_index'] as num?)?.toInt();
    return SourceRef(
      bookId: bookId,
      href: href.isEmpty ? null : href,
      chunkId: chunkId,
      jumpLink: href.isEmpty ? null : _jumpLink(bookId, href),
      sourceTitle: chapterTitle.isEmpty ? null : chapterTitle,
      locationLabel: chunkIndex == null ? null : 'Chunk $chunkIndex',
      sourceTextSnippet: snippet.isEmpty ? null : snippet,
      sourceTextForHash: snippet.isEmpty ? null : snippet,
      sourceKind: SourceRefKind.libraryRag,
      algorithmVersion: algorithmVersion,
      createdAt: (row['created_at'] as num?)?.toInt(),
      confidence: confidence,
    );
  }

  String _jumpLink(int bookId, String href) {
    return Uri(
      scheme: 'paperreader',
      host: 'reader',
      path: '/open',
      queryParameters: {
        'bookId': '$bookId',
        'href': href,
      },
    ).toString();
  }

  ConceptEdgeType _edgeType(String relation) {
    return switch (relation.trim()) {
      'supports' => ConceptEdgeType.supports,
      'contradicts' => ConceptEdgeType.contradicts,
      'depends_on' => ConceptEdgeType.dependsOn,
      'exemplifies' => ConceptEdgeType.exemplifies,
      _ => ConceptEdgeType.relatedTo,
    };
  }
}

class _DerivedNodeBuilder {
  _DerivedNodeBuilder({
    required this.dbId,
    required this.bookId,
    required this.name,
    required this.summary,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  final int dbId;
  final int bookId;
  final String name;
  final String summary;
  final double? confidence;
  final int? createdAt;
  final int? updatedAt;
  final List<SourceRef> sourceRefs = <SourceRef>[];

  String get nodeId => 'derived:book:$bookId:graph-node:$dbId';

  ConceptNode toConceptNode() {
    final label = name.isEmpty ? 'Graph node $dbId' : name;
    return ConceptNode(
      id: nodeId,
      type: ConceptNodeType.concept,
      label: label,
      summary:
          summary.isEmpty ? 'Derived full-book GraphRAG concept.' : summary,
      sourceRefs: sourceRefs,
      ownership: AiOutputOwnership.derivedCache,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
