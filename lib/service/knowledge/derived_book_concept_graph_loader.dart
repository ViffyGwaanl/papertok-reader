import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/tools/repository/books_repository.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';

typedef DerivedBookTitleLookup = Future<Map<int, String>> Function(
  Iterable<int> ids,
);

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

abstract class DerivedBookConceptGraphCatalog {
  Future<List<DerivedBookConceptGraphBook>> listBooks({int limit = 200});
}

class DerivedBookConceptGraphBook {
  const DerivedBookConceptGraphBook({
    required this.bookId,
    required this.title,
    required this.chunkCount,
    required this.raptorNodes,
    required this.graphNodes,
    required this.graphEdges,
    this.graphCommunities = 0,
  });

  final int bookId;
  final String title;
  final int chunkCount;
  final int raptorNodes;
  final int graphNodes;
  final int graphEdges;
  final int graphCommunities;

  bool get hasGlobalLayer => raptorNodes > 0;
  bool get hasGraphPreview => graphNodes > 0;
}

class AiGlobalDerivedBookConceptGraphCatalog
    implements DerivedBookConceptGraphCatalog {
  AiGlobalDerivedBookConceptGraphCatalog({
    AiIndexDatabase? database,
    DerivedBookTitleLookup? bookTitleLookup,
  })  : _database = database ?? AiIndexDatabase.instance,
        _bookTitleLookup = bookTitleLookup ?? _defaultBookTitleLookup;

  final AiIndexDatabase _database;
  final DerivedBookTitleLookup _bookTitleLookup;

  static Future<Map<int, String>> _defaultBookTitleLookup(
    Iterable<int> ids,
  ) async {
    final books = await const BooksRepository().fetchByIds(ids);
    return {
      for (final entry in books.entries) entry.key: entry.value.title,
    };
  }

  @override
  Future<List<DerivedBookConceptGraphBook>> listBooks({int limit = 200}) async {
    final db = await _database.database;
    final safeLimit = limit.clamp(1, 500).toInt();
    final rows = await db.rawQuery(
      '''
SELECT
  b.book_id,
  COALESCE(b.chunk_count, 0) AS chunk_count,
  COALESCE(r.raptor_nodes, 0) AS raptor_nodes,
  COALESCE(gn.graph_nodes, 0) AS graph_nodes,
  COALESCE(ge.graph_edges, 0) AS graph_edges,
  COALESCE(gc.graph_communities, 0) AS graph_communities,
  COALESCE(b.indexed_at, b.updated_at, b.created_at, 0) AS sort_ts
FROM ai_book_index b
LEFT JOIN (
  SELECT book_id, COUNT(*) AS raptor_nodes
  FROM ai_raptor_nodes
  GROUP BY book_id
) r ON r.book_id = b.book_id
LEFT JOIN (
  SELECT book_id, COUNT(*) AS graph_nodes
  FROM ai_graph_nodes
  GROUP BY book_id
) gn ON gn.book_id = b.book_id
LEFT JOIN (
  SELECT book_id, COUNT(*) AS graph_edges
  FROM ai_graph_edges
  GROUP BY book_id
) ge ON ge.book_id = b.book_id
LEFT JOIN (
  SELECT book_id, COUNT(*) AS graph_communities
  FROM ai_graph_communities
  GROUP BY book_id
) gc ON gc.book_id = b.book_id
WHERE COALESCE(b.chunk_count, 0) > 0
  AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
  AND (
    COALESCE(r.raptor_nodes, 0) > 0
    OR COALESCE(gn.graph_nodes, 0) > 0
  )
ORDER BY sort_ts DESC, b.book_id ASC
LIMIT ?
''',
      [safeLimit],
    );
    if (rows.isEmpty) return const <DerivedBookConceptGraphBook>[];

    final ids = rows
        .map((row) => (row['book_id'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toList(growable: false);
    final titles = await _bookTitleLookup(ids);

    return rows.map((row) {
      final bookId = (row['book_id'] as num?)?.toInt() ?? 0;
      final title = (titles[bookId] ?? '').trim();
      return DerivedBookConceptGraphBook(
        bookId: bookId,
        title: title.isEmpty ? 'Book #$bookId' : title,
        chunkCount: (row['chunk_count'] as num?)?.toInt() ?? 0,
        raptorNodes: (row['raptor_nodes'] as num?)?.toInt() ?? 0,
        graphNodes: (row['graph_nodes'] as num?)?.toInt() ?? 0,
        graphEdges: (row['graph_edges'] as num?)?.toInt() ?? 0,
        graphCommunities: (row['graph_communities'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }
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
WITH edge_scores AS (
  SELECT node_id, SUM(score) AS edge_score
  FROM (
    SELECT
      src_node_id AS node_id,
      10.0 + (COALESCE(weight, 0) * 6.0) + (COALESCE(evidence_count, 0) * 2.0) AS score
    FROM ai_graph_edges
    WHERE book_id = ?
    UNION ALL
    SELECT
      dst_node_id AS node_id,
      10.0 + (COALESCE(weight, 0) * 6.0) + (COALESCE(evidence_count, 0) * 2.0) AS score
    FROM ai_graph_edges
    WHERE book_id = ?
  )
  GROUP BY node_id
),
node_chunk_counts AS (
  SELECT node_id, COUNT(*) AS chunk_count
  FROM ai_graph_node_chunks
  GROUP BY node_id
),
ranked_nodes AS (
  SELECT
    gn.id,
    gn.name,
    gn.summary,
    gn.confidence,
    gn.created_at,
    gn.updated_at,
    COALESCE(nc.chunk_count, 0) AS chunk_count,
    (COALESCE(nc.chunk_count, 0) * 4.0)
      + COALESCE(es.edge_score, 0)
      + (COALESCE(gn.confidence, 0) * 0.1) AS node_score
  FROM ai_graph_nodes gn
  LEFT JOIN node_chunk_counts nc ON nc.node_id = gn.id
  LEFT JOIN edge_scores es ON es.node_id = gn.id
  WHERE gn.book_id = ?
    AND COALESCE(nc.chunk_count, 0) > 0
  ORDER BY node_score DESC,
           chunk_count DESC,
           COALESCE(gn.confidence, 0) DESC,
           gn.id ASC
  LIMIT ?
)
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
FROM ranked_nodes gn
LEFT JOIN ai_graph_node_chunks gnc ON gnc.node_id = gn.id
LEFT JOIN ai_chunks c ON c.id = gnc.chunk_id
ORDER BY gn.node_score DESC,
         gn.chunk_count DESC,
         COALESCE(gn.confidence, 0) DESC,
         gn.id ASC,
         c.id ASC
''',
      [bookId, bookId, bookId, safeLimit],
    );

    final builders = <int, _DerivedNodeBuilder>{};
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
