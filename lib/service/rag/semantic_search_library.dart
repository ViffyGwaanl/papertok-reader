import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_local_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:papertok_reader/service/rag/vector_math.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

typedef AiLibraryBookTitleResolver = Future<Map<int, String>> Function(
  Iterable<int> bookIds,
);

typedef AiEmbedQueryFn = Future<List<double>> Function(
  String query, {
  required String model,
  String? providerId,
});

typedef AiLibraryRerankFn = Future<List<double>> Function(
  String query,
  List<AiSemanticSearchLibraryRerankCandidate> candidates,
);

class AiSemanticSearchLibraryRerankCandidate {
  const AiSemanticSearchLibraryRerankCandidate({
    required this.chunkId,
    required this.bookId,
    required this.href,
    required this.anchor,
    required this.text,
    required this.score,
  });

  final int chunkId;
  final int bookId;
  final String href;
  final String anchor;
  final String text;
  final double score;
}

class AiSemanticSearchLibraryEvidence {
  const AiSemanticSearchLibraryEvidence({
    required this.bookId,
    required this.bookTitle,
    required this.href,
    required this.anchor,
    required this.snippet,
    required this.jumpLink,
    required this.score,
  });

  final int bookId;
  final String bookTitle;
  final String href;
  final String anchor;
  final String snippet;

  /// Best-effort navigation deep link.
  ///
  /// This uses Paper Reader's app URL scheme.
  final String jumpLink;

  final double score;

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'bookTitle': bookTitle,
        'href': href,
        'anchor': anchor,
        'snippet': snippet,
        'jumpLink': jumpLink,
        'score': score,
      };
}

class AiSemanticSearchLibraryResult {
  const AiSemanticSearchLibraryResult({
    required this.ok,
    required this.query,
    required this.evidence,
    this.message,
    this.usedFts,
    this.usedVectorFallback,
    this.indexedBooks,
    this.indexedChunks,
    this.candidates,
  });

  final bool ok;
  final String query;
  final List<AiSemanticSearchLibraryEvidence> evidence;
  final String? message;

  /// Whether the DB-level query used SQLite FTS5.
  final bool? usedFts;

  /// Whether we fell back to a small vector-only scan when text retrieval
  /// returned no candidates.
  final bool? usedVectorFallback;

  /// Diagnostics: number of indexed books included in the search scope.
  final int? indexedBooks;

  /// Diagnostics: total chunks (sum of chunk_count) across indexed books.
  final int? indexedChunks;

  /// Diagnostics: number of candidate rows used for vector/MMR ranking.
  final int? candidates;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'query': query,
        if (message != null) 'message': message,
        if (usedFts != null) 'usedFts': usedFts,
        if (usedVectorFallback != null)
          'usedVectorFallback': usedVectorFallback,
        if (indexedBooks != null) 'indexedBooks': indexedBooks,
        if (indexedChunks != null) 'indexedChunks': indexedChunks,
        if (candidates != null) 'candidates': candidates,
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
      };
}

class SemanticSearchLibrary {
  SemanticSearchLibrary({
    AiIndexDatabase? database,
    AiLibraryBookTitleResolver? resolveBookTitles,
    AiEmbedQueryFn? embedQuery,
    AiLibraryRerankFn? rerank,
    AiVectorSearchBackend? vectorSearch,
  })  : _db = database ?? AiIndexDatabase.instance,
        _resolveBookTitles = resolveBookTitles,
        _embedQuery = embedQuery,
        _rerank = rerank,
        _vectorIndex = AiLocalVectorIndex(
          backend: vectorSearch ?? const AiExactVectorSearchBackend(),
        );

  final AiIndexDatabase _db;
  final AiLibraryBookTitleResolver? _resolveBookTitles;
  final AiEmbedQueryFn? _embedQuery;
  final AiLibraryRerankFn? _rerank;
  final AiLocalVectorIndex _vectorIndex;

  static const double _mmrLambda = 0.72;

  Future<AiSemanticSearchLibraryResult> search({
    required String query,
    int maxResults = 6,
    bool onlyIndexed = true,
    List<String>? queryVariants,
    int neighborWindow = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return AiSemanticSearchLibraryResult(
        ok: false,
        query: query,
        evidence: const [],
        message: 'query must not be empty',
      );
    }

    final k = maxResults.clamp(1, 10);
    final candidateLimit = (k * 25).clamp(40, 240);
    final variants = _normalizeQueryVariants(
      trimmed,
      queryVariants: queryVariants,
    );

    final db = await _db.database;

    final hasFts = await _tableExists(db, 'ai_chunks_fts');
    final indexedFilter = onlyIndexed
        ? "b.chunk_count > 0 AND COALESCE(b.index_status, 'succeeded') = 'succeeded'"
        : '1=1';

    // Diagnostics: count indexed books/chunks in current scope.
    int? indexedBooks;
    int? indexedChunks;

    try {
      final stats = await db.rawQuery(
        '''
SELECT
  COUNT(*) AS indexed_books,
  COALESCE(SUM(chunk_count), 0) AS indexed_chunks
FROM ai_book_index b
WHERE ($indexedFilter)
''',
      );
      if (stats.isNotEmpty) {
        indexedBooks = (stats.first['indexed_books'] as num?)?.toInt();
        indexedChunks = (stats.first['indexed_chunks'] as num?)?.toInt();
      }
    } catch (_) {
      // Best-effort only.
    }

    var usedFts = false;
    List<Map<String, Object?>> rows = const [];

    if (hasFts) {
      final fused = <int, _FusedRow>{};
      try {
        for (final variant in variants) {
          final match = _buildFtsQuery(variant);
          if (match.isEmpty) continue;
          final fetched = await db.rawQuery(
            '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  c.text,
  c.raw_text,
  c.context_text,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  bm25(ai_chunks_fts) AS bm25,
  snippet(ai_chunks_fts, 0, '', '', '…', 18) AS snippet
FROM ai_chunks_fts
JOIN ai_chunks c ON c.id = ai_chunks_fts.rowid
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ai_chunks_fts MATCH ?
  AND ($indexedFilter)
ORDER BY bm25
LIMIT ?
''',
            [match, candidateLimit],
          );
          if (fetched.isNotEmpty) {
            usedFts = true;
            _mergeRowsByRrf(fused, fetched);
          }
        }
        rows = _rowsFromFusion(fused, limit: candidateLimit);
      } catch (e) {
        // FTS is optional; fall back to LIKE.
        AnxLog.warning('SemanticSearchLibrary: FTS query failed, fallback: $e');
        rows = const [];
        usedFts = false;
      }
    }

    if (rows.isEmpty) {
      // Fallback: naive LIKE scan.
      final fused = <int, _FusedRow>{};
      var hasSearchableVariant = false;

      for (final variant in variants) {
        final tokens = _tokenize(variant);
        if (tokens.isEmpty) continue;
        hasSearchableVariant = true;

        final whereParts = <String>[];
        final args = <Object?>[];

        for (final t in tokens.take(6)) {
          whereParts.add('c.text LIKE ?');
          args.add('%$t%');
        }

        final fetched = await db.rawQuery(
          '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  c.text,
  c.raw_text,
  c.context_text,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ($indexedFilter)
  AND (${whereParts.join(' OR ')})
LIMIT ?
''',
          [...args, candidateLimit],
        );
        _mergeRowsByRrf(fused, fetched);
      }

      if (!hasSearchableVariant) {
        return AiSemanticSearchLibraryResult(
          ok: false,
          query: query,
          evidence: const [],
          usedFts: false,
          indexedBooks: indexedBooks,
          indexedChunks: indexedChunks,
          message: 'query is not searchable',
        );
      }

      rows = _rowsFromFusion(fused, limit: candidateLimit);
      usedFts = false;
    }

    final globalRows = await _fetchGlobalLayerRows(
      db,
      variants: variants,
      indexedFilter: indexedFilter,
      limit: candidateLimit,
    );
    if (globalRows.isNotEmpty) {
      if (rows.isEmpty) {
        rows = globalRows;
      } else {
        final fused = <int, _FusedRow>{};
        _mergeRowsByRrf(fused, rows);
        _mergeRowsByRrf(fused, globalRows);
        rows = _rowsFromFusion(fused, limit: candidateLimit);
      }
    }

    // Cache query embeddings per (provider, model).
    final qVecByKey = <String, ({List<double> v, double norm})>{};

    Future<({List<double> v, double norm})> getQueryVec(
      String model, {
      String? providerId,
    }) async {
      final key = '${providerId ?? ''}|$model';
      final cached = qVecByKey[key];
      if (cached != null) return cached;

      final fn = _embedQuery;
      final qVec = fn != null
          ? await fn(trimmed, model: model, providerId: providerId)
          : await AiEmbeddingsService.embedQuery(
              trimmed,
              model: model,
              providerId: providerId,
            );

      final qNorm = VectorMath.l2Norm(qVec);
      final value = (v: qVec, norm: qNorm);
      qVecByKey[key] = value;
      return value;
    }

    var usedVectorFallback = false;

    if (rows.isEmpty && onlyIndexed) {
      // Final fallback: exact local vector search over indexed chunks.
      // The helper is intentionally isolated so an ANN/sqlite-vec backend can
      // replace the exact scanner without changing the search pipeline.
      final vectorLimit = (candidateLimit * 3).clamp(120, 360);
      final groups = await db.rawQuery(
        '''
SELECT DISTINCT
  COALESCE(provider_id, '') AS provider_id,
  COALESCE(embedding_model, '') AS embedding_model
FROM ai_book_index b
WHERE ($indexedFilter)
LIMIT 12
''',
      );
      final vectorRows = <Map<String, Object?>>[];
      for (final group in groups) {
        final model =
            (group['embedding_model']?.toString().trim().isNotEmpty ?? false)
                ? group['embedding_model']!.toString().trim()
                : AiEmbeddingsService.defaultEmbeddingModel;
        final providerId = (group['provider_id']?.toString() ?? '').trim();
        final q = await getQueryVec(
          model,
          providerId: providerId.isEmpty ? null : providerId,
        );
        vectorRows.addAll(
          await _vectorIndex.searchRows(
            db,
            queryVector: q.v,
            providerId: providerId,
            embeddingModel: model,
            limit: vectorLimit,
            onlyIndexed: onlyIndexed,
          ),
        );
      }
      vectorRows.sort((a, b) {
        final aScore = (a['local_vector_score'] as num?)?.toDouble() ?? 0.0;
        final bScore = (b['local_vector_score'] as num?)?.toDouble() ?? 0.0;
        final byScore = bScore.compareTo(aScore);
        if (byScore != 0) return byScore;
        final aId = (a['chunk_id'] as num?)?.toInt() ?? 0;
        final bId = (b['chunk_id'] as num?)?.toInt() ?? 0;
        return bId.compareTo(aId);
      });
      rows = vectorRows.take(vectorLimit).toList(growable: false);

      if (rows.isNotEmpty) {
        usedVectorFallback = true;
      }
    }

    if (rows.isEmpty) {
      final hasAnyIndexed = (indexedChunks ?? 0) > 0;
      final defaultMessage = onlyIndexed
          ? (hasAnyIndexed
              ? 'Indexed content exists, but no candidates matched. Try fewer keywords or rebuild the index.'
              : 'No indexed books found. Build AI indexes from Library → AI Index.')
          : 'No content matched.';

      return AiSemanticSearchLibraryResult(
        ok: false,
        query: query,
        evidence: const [],
        usedFts: usedFts,
        usedVectorFallback: usedVectorFallback,
        indexedBooks: indexedBooks,
        indexedChunks: indexedChunks,
        candidates: 0,
        message: defaultMessage,
      );
    }

    // Resolve book titles (best-effort).
    final bookIds = rows
        .map((r) => (r['book_id'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toSet();

    Map<int, String> titles = const {};
    if (_resolveBookTitles != null && bookIds.isNotEmpty) {
      try {
        titles = await _resolveBookTitles(bookIds);
      } catch (e) {
        AnxLog.warning('SemanticSearchLibrary: book title resolver failed: $e');
      }
    }

    // Collect candidates.
    final candidates = <_Candidate>[];
    for (final r in rows) {
      final bookId = (r['book_id'] as num?)?.toInt() ?? 0;
      if (bookId <= 0) continue;

      final vec = AiVectorCodec.decodeVector(
        blob: r['embedding_blob'],
        jsonText: r['embedding_json']?.toString(),
      );
      if (vec == null || vec.isEmpty) continue;

      final model =
          (r['embedding_model']?.toString().trim().isNotEmpty ?? false)
              ? r['embedding_model']!.toString().trim()
              : AiEmbeddingsService.defaultEmbeddingModel;

      final providerId = (r['provider_id']?.toString() ?? '').trim();

      final q = await getQueryVec(
        model,
        providerId: providerId.isEmpty ? null : providerId,
      );
      final vNorm = (r['embedding_norm'] as num?)?.toDouble();
      final sim = VectorMath.cosineSimilarity(
        q.v,
        vec,
        aNorm: q.norm,
        bNorm: vNorm,
      );
      final vecScore = ((sim + 1) / 2).clamp(0.0, 1.0);

      candidates.add(
        _Candidate(
          row: r,
          chunkId: (r['chunk_id'] as num?)?.toInt() ?? 0,
          bookId: bookId,
          model: model,
          vector: vec,
          vectorNorm: vNorm,
          vectorScore: vecScore,
        ),
      );
    }

    if (candidates.isEmpty) {
      return AiSemanticSearchLibraryResult(
        ok: false,
        query: query,
        evidence: const [],
        usedFts: usedFts,
        usedVectorFallback: usedVectorFallback,
        indexedBooks: indexedBooks,
        indexedChunks: indexedChunks,
        candidates: rows.length,
        message: 'No valid embedding vectors found. Please rebuild indexes.',
      );
    }

    // Normalize rank fusion / BM25 into [0,1] (1 = best) when available.
    final rrfVals = <double>[];
    for (final c in candidates) {
      final raw = c.row['rrf_score'];
      if (raw is num) rrfVals.add(raw.toDouble());
    }
    if (rrfVals.isNotEmpty) {
      final maxV = rrfVals.reduce((a, b) => a > b ? a : b);
      if (maxV > 0) {
        for (final c in candidates) {
          final raw = c.row['rrf_score'];
          if (raw is num) {
            c.textScore = (raw.toDouble() / maxV).clamp(0.0, 1.0);
          }
        }
      }
    } else if (usedFts) {
      final bm25Vals = <double>[];
      for (final c in candidates) {
        final raw = c.row['bm25'];
        if (raw is num) bm25Vals.add(raw.toDouble());
      }
      if (bm25Vals.isNotEmpty) {
        final minV = bm25Vals.reduce((a, b) => a < b ? a : b);
        final maxV = bm25Vals.reduce((a, b) => a > b ? a : b);
        final span = (maxV - minV).abs();
        for (final c in candidates) {
          final raw = c.row['bm25'];
          if (raw is num) {
            final v = raw.toDouble();
            final normalized = span == 0 ? 1.0 : (1.0 - ((v - minV) / span));
            c.textScore = normalized.clamp(0.0, 1.0);
          }
        }
      }
    }

    // Hybrid score.
    for (final c in candidates) {
      final textWeight = usedFts ? 0.35 : 0.0;
      final vecWeight = 1.0 - textWeight;
      c.hybridScore =
          (vecWeight * c.vectorScore) + (textWeight * (c.textScore ?? 0.0));
    }

    // Sort by hybrid score (for stable tie-breaking).
    candidates.sort((a, b) => b.hybridScore.compareTo(a.hybridScore));

    await _applyRerank(trimmed, candidates);

    // Sort again after optional reranking.
    candidates.sort((a, b) => b.hybridScore.compareTo(a.hybridScore));

    final selected = _selectWithMmr(candidates, k);

    final evidence = <AiSemanticSearchLibraryEvidence>[];
    for (final c in selected) {
      final r = c.row;
      final href = r['chapter_href']?.toString() ?? '';
      final title = (r['chapter_title']?.toString() ?? '').trim();
      final anchor = title.isEmpty ? href : title;

      final snippet = await _buildEvidenceSnippet(
        db,
        c,
        usedFts: usedFts,
        neighborWindow: neighborWindow,
      );

      final jumpLink = PaperReaderReaderIntent(
        bookId: c.bookId,
        href: href,
      ).toUri().toString();

      evidence.add(AiSemanticSearchLibraryEvidence(
        bookId: c.bookId,
        bookTitle: (titles[c.bookId] ?? '').trim(),
        href: href,
        anchor: anchor,
        snippet: snippet,
        jumpLink: jumpLink,
        score: c.hybridScore,
      ));
    }

    return AiSemanticSearchLibraryResult(
      ok: true,
      query: query,
      evidence: evidence,
      usedFts: usedFts,
      usedVectorFallback: usedVectorFallback,
      indexedBooks: indexedBooks,
      indexedChunks: indexedChunks,
      candidates: rows.length,
    );
  }

  List<_Candidate> _selectWithMmr(List<_Candidate> candidates, int k) {
    final selected = <_Candidate>[];
    final remaining = List<_Candidate>.from(candidates);

    while (selected.length < k && remaining.isNotEmpty) {
      _Candidate? best;
      var bestScore = -1e9;

      for (final c in remaining) {
        final rel = c.hybridScore;

        // Diversity penalty: max similarity to already-selected items.
        var maxSim = 0.0;
        for (final s in selected) {
          final sim = VectorMath.cosineSimilarity(
            c.vector,
            s.vector,
            aNorm: c.vectorNorm,
            bNorm: s.vectorNorm,
          );
          final sim01 = ((sim + 1) / 2).clamp(0.0, 1.0);
          if (sim01 > maxSim) maxSim = sim01;
        }

        final mmr = (_mmrLambda * rel) - ((1.0 - _mmrLambda) * maxSim);
        if (mmr > bestScore) {
          bestScore = mmr;
          best = c;
        }
      }

      if (best == null) break;
      final picked = best;
      selected.add(picked);
      remaining.remove(picked);

      // Extra dedupe: avoid returning many chunks from the same chapter.
      remaining.removeWhere((c) {
        if (c.bookId != picked.bookId) return false;
        final h1 = c.row['chapter_href']?.toString() ?? '';
        final h2 = picked.row['chapter_href']?.toString() ?? '';
        return h1.isNotEmpty && h1 == h2;
      });
    }

    return selected;
  }

  Future<void> _applyRerank(
    String query,
    List<_Candidate> candidates,
  ) async {
    final rerank = _rerank;
    if (rerank == null || candidates.isEmpty) return;

    final inputs = candidates
        .map(
          (c) => AiSemanticSearchLibraryRerankCandidate(
            chunkId: c.chunkId,
            bookId: c.bookId,
            href: c.row['chapter_href']?.toString() ?? '',
            anchor: (c.row['chapter_title']?.toString() ?? '').trim(),
            text: c.row['text']?.toString() ?? '',
            score: c.hybridScore,
          ),
        )
        .toList(growable: false);

    List<double> scores;
    try {
      scores = await rerank(query, inputs);
    } catch (e) {
      AnxLog.warning('SemanticSearchLibrary: rerank failed, skip: $e');
      return;
    }
    if (scores.length != candidates.length) {
      AnxLog.warning(
        'SemanticSearchLibrary: rerank returned ${scores.length} scores '
        'for ${candidates.length} candidates, skip',
      );
      return;
    }

    for (var i = 0; i < candidates.length; i++) {
      final rerankScore = scores[i].clamp(0.0, 1.0).toDouble();
      candidates[i].rerankScore = rerankScore;
      candidates[i].hybridScore =
          (0.30 * candidates[i].hybridScore) + (0.70 * rerankScore);
    }
  }

  Future<List<Map<String, Object?>>> _fetchGlobalLayerRows(
    Database db, {
    required List<String> variants,
    required String indexedFilter,
    required int limit,
  }) async {
    final tokens = variants.expand(_tokenize).take(8).toSet().toList();
    if (tokens.isEmpty) return const [];

    final hasRaptor = await _tableExists(db, 'ai_raptor_nodes');
    final hasGraph = await _tableExists(db, 'ai_graph_communities');
    if (!hasRaptor && !hasGraph) return const [];

    final whereParts = <String>[];
    final args = <Object?>[];
    for (final token in tokens) {
      whereParts.add('(summary LIKE ? OR title LIKE ?)');
      args
        ..add('%$token%')
        ..add('%$token%');
    }
    final summaryWhere = whereParts.join(' OR ');
    final safeLimit = limit.clamp(1, 240);
    final out = <Map<String, Object?>>[];

    if (hasRaptor) {
      out.addAll(
        await db.rawQuery(
          '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  r.summary AS text,
  r.summary AS raw_text,
  c.context_text,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  r.level AS global_level,
  'raptor' AS global_layer
FROM ai_raptor_nodes r
JOIN ai_raptor_node_chunks rc ON rc.node_id = r.id
JOIN ai_chunks c ON c.id = rc.chunk_id
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ($indexedFilter)
  AND ($summaryWhere)
ORDER BY r.level DESC, COALESCE(r.updated_at, 0) DESC, r.id DESC
LIMIT ?
''',
          [...args, safeLimit],
        ),
      );
    }

    if (hasGraph && out.length < safeLimit) {
      out.addAll(
        await db.rawQuery(
          '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  gc.summary AS text,
  gc.summary AS raw_text,
  c.context_text,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  gc.level AS global_level,
  'graph' AS global_layer
FROM ai_graph_communities gc
JOIN ai_graph_community_nodes gcn ON gcn.community_id = gc.id
JOIN ai_graph_node_chunks gnc ON gnc.node_id = gcn.node_id
JOIN ai_chunks c ON c.id = gnc.chunk_id
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ($indexedFilter)
  AND ($summaryWhere)
ORDER BY gc.level DESC, COALESCE(gc.updated_at, 0) DESC, gc.id DESC
LIMIT ?
''',
          [...args, safeLimit - out.length],
        ),
      );
    }

    final seen = <int>{};
    return out
        .where((row) {
          final id = (row['chunk_id'] as num?)?.toInt() ?? 0;
          return id > 0 && seen.add(id);
        })
        .take(safeLimit)
        .toList(growable: false);
  }

  Future<String> _buildEvidenceSnippet(
    Database db,
    _Candidate candidate, {
    required bool usedFts,
    required int neighborWindow,
  }) async {
    final fallback = _baseSnippet(candidate.row, usedFts: usedFts);
    if ((candidate.row['global_layer']?.toString() ?? '').isNotEmpty) {
      return fallback;
    }
    final window = neighborWindow.clamp(0, 3);
    if (window <= 0) return fallback;

    final href = candidate.row['chapter_href']?.toString() ?? '';
    if (href.isEmpty) return fallback;

    final chunkIndex = (candidate.row['chunk_index'] as num?)?.toInt();
    if (chunkIndex == null) return fallback;

    final rows = await db.query(
      'ai_chunks',
      columns: ['chunk_index', 'text', 'raw_text'],
      where: '''
book_id = ?
AND chapter_href = ?
AND chunk_index BETWEEN ? AND ?
''',
      whereArgs: [
        candidate.bookId,
        href,
        chunkIndex - window,
        chunkIndex + window,
      ],
      orderBy: 'chunk_index ASC',
      limit: (window * 2) + 1,
    );

    if (rows.isEmpty) return fallback;
    final merged = rows
        .map((r) => _rowDisplayText(r))
        .where((text) => text.isNotEmpty)
        .join('\n\n');
    if (merged.isEmpty) return fallback;
    return _truncateSnippet(merged, 1200);
  }

  String _baseSnippet(
    Map<String, Object?> row, {
    required bool usedFts,
  }) {
    if (usedFts) {
      final snippet = (row['snippet']?.toString() ?? '').trim();
      if (snippet.isNotEmpty) return snippet;
    }
    return _truncateSnippet(_rowDisplayText(row), 450);
  }

  String _rowDisplayText(Map<String, Object?> row) {
    final raw = (row['raw_text']?.toString() ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return (row['text']?.toString() ?? '').trim();
  }

  String _truncateSnippet(String text, int maxChars) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}…';
  }

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return rows.isNotEmpty;
  }

  List<String> _normalizeQueryVariants(
    String query, {
    List<String>? queryVariants,
  }) {
    final out = <String>[];

    void add(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!out.contains(v)) out.add(v);
    }

    add(query);
    for (final v in queryVariants ?? const <String>[]) {
      add(v);
    }

    final tokens = _tokenize(query);
    if (tokens.length > 1) {
      add(tokens.join(' '));
    }

    return out;
  }

  void _mergeRowsByRrf(
    Map<int, _FusedRow> fused,
    List<Map<String, Object?>> rows,
  ) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final chunkId = (row['chunk_id'] as num?)?.toInt() ?? 0;
      if (chunkId <= 0) continue;
      final entry = fused.putIfAbsent(chunkId, () => _FusedRow(row));
      entry.add(row, rank: i + 1);
    }
  }

  List<Map<String, Object?>> _rowsFromFusion(
    Map<int, _FusedRow> fused, {
    required int limit,
  }) {
    final entries = fused.values.toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    return entries
        .take(limit)
        .map((e) => <String, Object?>{
              ...e.row,
              'rrf_score': e.score,
            })
        .toList(growable: false);
  }

  String _buildFtsQuery(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return '';

    // Use OR semantics to maximize recall.
    //
    // Rationale:
    // - The final ranking uses vectors + (optional) BM25 + MMR.
    // - Many queries contain mixed-language tokens (e.g. "GLM-5 论文 ...").
    //   AND semantics would often return zero candidates, preventing the vector
    //   stage from running at all.
    //
    // Important: SQLite FTS5 query syntax treats certain characters as
    // operators. For example, `GLM-5` can raise `no such column: 5`.
    //
    // To keep search robust across languages and model/version-like tokens
    // (gpt-4o, glm-5, etc.), we quote any token that contains non-word
    // characters.
    return tokens.take(8).map(_escapeFtsToken).join(' OR ');
  }

  static final RegExp _ftsSafeToken = RegExp(r'^[0-9A-Za-z_\u4e00-\u9fff]+$');

  String _escapeFtsToken(String token) {
    if (_ftsSafeToken.hasMatch(token)) {
      return token;
    }

    // Escape embedded quotes for FTS phrase syntax.
    final escaped = token.replaceAll('"', '""');
    return '"$escaped"';
  }

  @visibleForTesting
  String debugBuildFtsQuery(String query) => _buildFtsQuery(query);

  List<String> _tokenize(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'''["'\[\]\(\)\{\}:;]+'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];

    final raw = cleaned.split(' ');
    final out = <String>[];
    for (final t in raw) {
      final s = t.trim();
      if (s.isEmpty) continue;
      // FTS syntax can be picky; keep tokens small.
      if (s.length > 40) {
        out.add(s.substring(0, 40));
      } else {
        out.add(s);
      }
    }
    return out;
  }
}

class _Candidate {
  _Candidate({
    required this.row,
    required this.chunkId,
    required this.bookId,
    required this.model,
    required this.vector,
    required this.vectorNorm,
    required this.vectorScore,
  });

  final Map<String, Object?> row;
  final int chunkId;
  final int bookId;
  final String model;
  final List<double> vector;
  final double? vectorNorm;

  final double vectorScore;
  double? textScore;
  double? rerankScore;
  double hybridScore = 0;
}

class _FusedRow {
  _FusedRow(this.row);

  Map<String, Object?> row;
  double score = 0;

  void add(Map<String, Object?> next, {required int rank}) {
    score += 1.0 / (60 + rank);

    final nextBm25 = next['bm25'];
    final currentBm25 = row['bm25'];
    if (nextBm25 is num &&
        (currentBm25 is! num || nextBm25.toDouble() < currentBm25.toDouble())) {
      row = next;
    }
  }
}
