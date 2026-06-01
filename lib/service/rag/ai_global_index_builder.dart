import 'dart:math' as math;

import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

typedef AiGlobalIndexBackfillCancellationCheck = bool Function();
typedef AiGlobalIndexBackfillProgressCallback = void Function(
  AiGlobalIndexBackfillProgress progress,
);

class AiGlobalIndexStats {
  const AiGlobalIndexStats({
    required this.raptorNodes,
    required this.graphNodes,
    required this.graphEdges,
    required this.graphCommunities,
  });

  final int raptorNodes;
  final int graphNodes;
  final int graphEdges;
  final int graphCommunities;
}

class AiGlobalIndexBookLayerStatus {
  const AiGlobalIndexBookLayerStatus({
    required this.bookId,
    required this.chunkCount,
    required this.raptorNodes,
    required this.graphNodes,
    required this.graphEdges,
    required this.graphCommunities,
  });

  final int bookId;
  final int chunkCount;
  final int raptorNodes;
  final int graphNodes;
  final int graphEdges;
  final int graphCommunities;

  /// RAPTOR nodes are the durable marker that a book has a global layer.
  ///
  /// Graph nodes can legitimately be empty for non-English or very short books
  /// with the current deterministic extractor, so they must not be used as the
  /// "missing global layer" signal.
  bool get hasGlobalLayer => raptorNodes > 0;
}

class AiGlobalIndexBackfillProgress {
  const AiGlobalIndexBackfillProgress({
    required this.bookId,
    required this.done,
    required this.total,
    required this.stats,
  });

  final int bookId;
  final int done;
  final int total;
  final AiGlobalIndexStats stats;

  double get progress {
    if (total <= 0) return 0;
    return (done / total).clamp(0.0, 1.0).toDouble();
  }
}

class AiGlobalIndexBackfillResult {
  const AiGlobalIndexBackfillResult({
    required this.totalCandidates,
    required this.rebuiltBookIds,
    required this.failedBookIds,
    this.cancelled = false,
  });

  final int totalCandidates;
  final List<int> rebuiltBookIds;
  final List<int> failedBookIds;
  final bool cancelled;

  bool get ok => failedBookIds.isEmpty;
}

class AiGlobalIndexBuilder {
  AiGlobalIndexBuilder({AiIndexDatabase? database})
      : _database = database ?? AiIndexDatabase.instance;

  final AiIndexDatabase _database;

  Future<AiGlobalIndexBookLayerStatus?> getBookLayerStatus(int bookId) async {
    if (bookId <= 0) return null;
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
SELECT
  b.book_id,
  COALESCE(b.chunk_count, 0) AS chunk_count,
  COALESCE(r.raptor_nodes, 0) AS raptor_nodes,
  COALESCE(gn.graph_nodes, 0) AS graph_nodes,
  COALESCE(ge.graph_edges, 0) AS graph_edges,
  COALESCE(gc.graph_communities, 0) AS graph_communities
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
WHERE b.book_id = ?
  AND COALESCE(b.chunk_count, 0) > 0
  AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
LIMIT 1
''',
      [bookId],
    );
    if (rows.isEmpty) return null;
    return _mapLayerStatus(rows.first);
  }

  Future<List<AiGlobalIndexBookLayerStatus>> listBooksMissingGlobalLayer({
    int limit = 500,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
SELECT
  b.book_id,
  COALESCE(b.chunk_count, 0) AS chunk_count,
  COALESCE(r.raptor_nodes, 0) AS raptor_nodes,
  COALESCE(gn.graph_nodes, 0) AS graph_nodes,
  COALESCE(ge.graph_edges, 0) AS graph_edges,
  COALESCE(gc.graph_communities, 0) AS graph_communities
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
  AND COALESCE(r.raptor_nodes, 0) = 0
ORDER BY COALESCE(b.indexed_at, b.updated_at, b.created_at, 0) DESC,
  b.book_id ASC
LIMIT ?
''',
      [limit.clamp(1, 5000)],
    );

    return rows.map(_mapLayerStatus).toList(growable: false);
  }

  Future<AiGlobalIndexBackfillResult> backfillMissingGlobalLayers({
    int limit = 500,
    int? nowMs,
    AiGlobalIndexBackfillCancellationCheck? shouldCancel,
    AiGlobalIndexBackfillProgressCallback? onProgress,
  }) async {
    final candidates = await listBooksMissingGlobalLayer(limit: limit);
    final rebuilt = <int>[];
    final failed = <int>[];
    var cancelled = false;

    for (var i = 0; i < candidates.length; i++) {
      final status = candidates[i];
      if (shouldCancel?.call() == true) {
        cancelled = true;
        break;
      }
      try {
        final stats = await rebuildBook(bookId: status.bookId, nowMs: nowMs);
        rebuilt.add(status.bookId);
        onProgress?.call(
          AiGlobalIndexBackfillProgress(
            bookId: status.bookId,
            done: i + 1,
            total: candidates.length,
            stats: stats,
          ),
        );
      } catch (e) {
        failed.add(status.bookId);
        AnxLog.warning(
          'AiGlobalIndex: backfill failed bookId=${status.bookId} error=$e',
        );
      }
    }

    return AiGlobalIndexBackfillResult(
      totalCandidates: candidates.length,
      rebuiltBookIds: rebuilt,
      failedBookIds: failed,
      cancelled: cancelled,
    );
  }

  AiGlobalIndexBookLayerStatus _mapLayerStatus(Map<String, Object?> row) {
    return AiGlobalIndexBookLayerStatus(
      bookId: (row['book_id'] as num?)?.toInt() ?? 0,
      chunkCount: (row['chunk_count'] as num?)?.toInt() ?? 0,
      raptorNodes: (row['raptor_nodes'] as num?)?.toInt() ?? 0,
      graphNodes: (row['graph_nodes'] as num?)?.toInt() ?? 0,
      graphEdges: (row['graph_edges'] as num?)?.toInt() ?? 0,
      graphCommunities: (row['graph_communities'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AiGlobalIndexStats> rebuildBook({
    required int bookId,
    int? nowMs,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'ai_chunks',
      columns: [
        'id',
        'chapter_href',
        'chapter_title',
        'chapter_order',
        'chunk_index',
        'raw_text',
        'text',
      ],
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy:
          'COALESCE(chapter_order, 0) ASC, chapter_href ASC, chunk_index ASC',
    );

    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (rows.isEmpty) {
      await _clearBook(db, bookId);
      return const AiGlobalIndexStats(
        raptorNodes: 0,
        graphNodes: 0,
        graphEdges: 0,
        graphCommunities: 0,
      );
    }

    var raptorNodes = 0;
    var graphNodes = 0;
    var graphEdges = 0;
    var graphCommunities = 0;

    await db.transaction((txn) async {
      await _clearBook(txn, bookId);

      final chapters = _groupByChapter(rows);
      final chapterSummaries = <String>[];
      for (final chapter in chapters) {
        final summary = _chapterSummary(chapter);
        chapterSummaries.add(summary);
        final nodeId = await txn.insert('ai_raptor_nodes', {
          'book_id': bookId,
          'level': 1,
          'parent_id': null,
          'cluster_id': chapter.href,
          'title': chapter.title,
          'summary': summary,
          'child_count': chapter.rows.length,
          'created_at': ts,
          'updated_at': ts,
        });
        raptorNodes++;
        for (final row in chapter.rows) {
          await txn.insert('ai_raptor_node_chunks', {
            'node_id': nodeId,
            'chunk_id': row.id,
          });
        }
      }

      final bookSummary = _bookSummary(chapterSummaries);
      final bookNodeId = await txn.insert('ai_raptor_nodes', {
        'book_id': bookId,
        'level': 2,
        'parent_id': null,
        'cluster_id': 'book:$bookId',
        'title': 'Book summary',
        'summary': bookSummary,
        'child_count': rows.length,
        'created_at': ts,
        'updated_at': ts,
      });
      raptorNodes++;
      for (final row in rows) {
        await txn.insert('ai_raptor_node_chunks', {
          'node_id': bookNodeId,
          'chunk_id': (row['id'] as num).toInt(),
        });
      }

      final graph = _buildGraph(rows);
      final nodeIds = <String, int>{};
      for (final node in graph.nodes) {
        final nodeId = await txn.insert('ai_graph_nodes', {
          'book_id': bookId,
          'node_type': 'term',
          'name': node.term,
          'canonical_name': node.term,
          'summary': node.summary,
          'confidence': node.confidence,
          'created_at': ts,
          'updated_at': ts,
        });
        nodeIds[node.term] = nodeId;
        graphNodes++;
        for (final chunkId in node.chunkIds.take(12)) {
          await txn.insert('ai_graph_node_chunks', {
            'node_id': nodeId,
            'chunk_id': chunkId,
            'role': 'mention',
          });
        }
      }

      for (final edge in graph.edges) {
        final src = nodeIds[edge.src];
        final dst = nodeIds[edge.dst];
        if (src == null || dst == null) continue;
        await txn.insert('ai_graph_edges', {
          'book_id': bookId,
          'src_node_id': src,
          'dst_node_id': dst,
          'relation': 'co_occurs',
          'weight': edge.weight,
          'evidence_count': edge.evidenceCount,
          'created_at': ts,
          'updated_at': ts,
        });
        graphEdges++;
      }

      if (nodeIds.isNotEmpty) {
        final communityId = await txn.insert('ai_graph_communities', {
          'book_id': bookId,
          'level': 0,
          'title': 'Key themes',
          'summary': _communitySummary(graph.nodes),
          'created_at': ts,
          'updated_at': ts,
        });
        graphCommunities++;
        for (final nodeId in nodeIds.values) {
          await txn.insert('ai_graph_community_nodes', {
            'community_id': communityId,
            'node_id': nodeId,
          });
        }
      }
    });

    return AiGlobalIndexStats(
      raptorNodes: raptorNodes,
      graphNodes: graphNodes,
      graphEdges: graphEdges,
      graphCommunities: graphCommunities,
    );
  }

  Future<void> _clearBook(DatabaseExecutor db, int bookId) async {
    await db.delete(
      'ai_raptor_nodes',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await db.delete(
      'ai_graph_communities',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await db.delete(
      'ai_graph_nodes',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  List<_ChapterRows> _groupByChapter(List<Map<String, Object?>> rows) {
    final out = <_ChapterRows>[];
    _ChapterRows? current;
    for (final row in rows) {
      final href = row['chapter_href']?.toString() ?? '';
      if (current == null || current.href != href) {
        current = _ChapterRows(
          href: href,
          title: (row['chapter_title']?.toString() ?? '').trim(),
          rows: [],
        );
        out.add(current);
      }
      current.rows.add(_ChunkRow.from(row));
    }
    return out;
  }

  String _chapterSummary(_ChapterRows chapter) {
    final title = chapter.title.isEmpty ? chapter.href : chapter.title;
    final text = _compactText(
      chapter.rows.map((row) => row.displayText).join('\n\n'),
      900,
    );
    return 'Chapter summary: $title. $text';
  }

  String _bookSummary(List<String> chapterSummaries) {
    final text = _compactText(chapterSummaries.join('\n\n'), 1200);
    return 'Book summary: $text';
  }

  String _communitySummary(List<_GraphNode> nodes) {
    final terms = nodes.take(8).map((node) => node.term).join(', ');
    final evidence = nodes.take(4).map((node) => node.summary).join(' ');
    return 'GraphRAG community: Key themes: $terms. $evidence';
  }

  _GraphBuild _buildGraph(List<Map<String, Object?>> rows) {
    final byTerm = <String, _TermStats>{};
    final chunkTerms = <int, Set<String>>{};

    for (final row in rows) {
      final chunk = _ChunkRow.from(row);
      final terms = _extractTerms(
        '${row['chapter_title'] ?? ''}\n${chunk.displayText}',
      );
      if (terms.isEmpty) continue;
      chunkTerms[chunk.id] = terms;
      for (final term in terms) {
        final stats = byTerm.putIfAbsent(term, () => _TermStats(term));
        stats
          ..count += 1
          ..chunkIds.add(chunk.id);
      }
    }

    final topTerms = byTerm.values.toList(growable: false)
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.term.compareTo(b.term);
      });
    final selected = topTerms.take(12).toList(growable: false);
    final selectedTerms = selected.map((e) => e.term).toSet();

    final nodes = [
      for (final stats in selected)
        _GraphNode(
          term: stats.term,
          confidence: math.min(1.0, 0.35 + (stats.count * 0.12)),
          chunkIds: stats.chunkIds.toList(growable: false),
          summary:
              "Theme '${stats.term}' appears in ${stats.chunkIds.length} indexed passage(s).",
        ),
    ];

    final edgeStats = <String, _GraphEdge>{};
    for (final entry in chunkTerms.entries) {
      final terms = entry.value
          .where(selectedTerms.contains)
          .toList(growable: false)
        ..sort();
      for (var i = 0; i < terms.length; i++) {
        for (var j = i + 1; j < terms.length; j++) {
          final key = '${terms[i]}\u0000${terms[j]}';
          final edge = edgeStats.putIfAbsent(
            key,
            () => _GraphEdge(
              src: terms[i],
              dst: terms[j],
              weight: 0,
              evidenceCount: 0,
            ),
          );
          edge
            ..weight += 1
            ..evidenceCount += 1;
        }
      }
    }

    final edges = edgeStats.values.toList(growable: false)
      ..sort((a, b) {
        final byEvidence = b.evidenceCount.compareTo(a.evidenceCount);
        return byEvidence != 0 ? byEvidence : a.src.compareTo(b.src);
      });

    return _GraphBuild(
      nodes: nodes,
      edges: edges.take(24).toList(growable: false),
    );
  }

  Set<String> _extractTerms(String text) {
    final matches = RegExp(r'[A-Za-z][A-Za-z0-9_-]{3,}')
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0) ?? '')
        .where((term) => term.length >= 4 && !_stopWords.contains(term));
    return matches.take(32).toSet();
  }

  String _compactText(String value, int maxChars) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trim()}...';
  }

  static const Set<String> _stopWords = {
    'about',
    'after',
    'also',
    'another',
    'book',
    'chapter',
    'first',
    'from',
    'into',
    'local',
    'only',
    'ordinary',
    'passage',
    'summary',
    'text',
    'that',
    'their',
    'there',
    'this',
    'with',
  };
}

class _ChunkRow {
  const _ChunkRow({
    required this.id,
    required this.displayText,
  });

  factory _ChunkRow.from(Map<String, Object?> row) {
    final raw = (row['raw_text']?.toString() ?? '').trim();
    final text = raw.isNotEmpty ? raw : (row['text']?.toString() ?? '').trim();
    return _ChunkRow(
      id: (row['id'] as num).toInt(),
      displayText: text,
    );
  }

  final int id;
  final String displayText;
}

class _ChapterRows {
  _ChapterRows({
    required this.href,
    required this.title,
    required this.rows,
  });

  final String href;
  final String title;
  final List<_ChunkRow> rows;
}

class _TermStats {
  _TermStats(this.term);

  final String term;
  int count = 0;
  final Set<int> chunkIds = <int>{};
}

class _GraphBuild {
  const _GraphBuild({
    required this.nodes,
    required this.edges,
  });

  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
}

class _GraphNode {
  const _GraphNode({
    required this.term,
    required this.summary,
    required this.confidence,
    required this.chunkIds,
  });

  final String term;
  final String summary;
  final double confidence;
  final List<int> chunkIds;
}

class _GraphEdge {
  _GraphEdge({
    required this.src,
    required this.dst,
    required this.weight,
    required this.evidenceCount,
  });

  final String src;
  final String dst;
  double weight;
  int evidenceCount;
}
