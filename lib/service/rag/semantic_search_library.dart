import 'dart:convert';

import 'package:anx_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:meta/meta.dart';
import 'package:anx_reader/service/rag/ai_embeddings_service.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/vector_math.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

typedef AiLibraryBookTitleResolver = Future<Map<int, String>> Function(
  Iterable<int> bookIds,
);

typedef AiEmbedQueryFn = Future<List<double>> Function(
  String query, {
  required String model,
  String? providerId,
});

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

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'query': query,
        if (message != null) 'message': message,
        if (usedFts != null) 'usedFts': usedFts,
        if (usedVectorFallback != null)
          'usedVectorFallback': usedVectorFallback,
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
      };
}

class SemanticSearchLibrary {
  SemanticSearchLibrary({
    AiIndexDatabase? database,
    AiLibraryBookTitleResolver? resolveBookTitles,
    AiEmbedQueryFn? embedQuery,
  })  : _db = database ?? AiIndexDatabase.instance,
        _resolveBookTitles = resolveBookTitles,
        _embedQuery = embedQuery;

  final AiIndexDatabase _db;
  final AiLibraryBookTitleResolver? _resolveBookTitles;
  final AiEmbedQueryFn? _embedQuery;

  static const double _mmrLambda = 0.72;

  Future<AiSemanticSearchLibraryResult> search({
    required String query,
    int maxResults = 6,
    bool onlyIndexed = true,
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

    final db = await _db.database;

    final hasFts = await _tableExists(db, 'ai_chunks_fts');
    final indexedFilter = onlyIndexed
        ? "b.chunk_count > 0 AND COALESCE(b.index_status, 'succeeded') = 'succeeded'"
        : '1=1';

    var usedFts = false;
    List<Map<String, Object?>> rows = const [];

    if (hasFts) {
      final match = _buildFtsQuery(trimmed);
      if (match.isNotEmpty) {
        try {
          rows = await db.rawQuery(
            '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.text,
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
          usedFts = true;
        } catch (e) {
          // FTS is optional; fall back to LIKE.
          AnxLog.warning(
              'SemanticSearchLibrary: FTS query failed, fallback: $e');
          rows = const [];
          usedFts = false;
        }
      }
    }

    if (rows.isEmpty) {
      // Fallback: naive LIKE scan.
      final tokens = _tokenize(trimmed);
      if (tokens.isEmpty) {
        return AiSemanticSearchLibraryResult(
          ok: false,
          query: query,
          evidence: const [],
          usedFts: false,
          message: 'query is not searchable',
        );
      }

      final whereParts = <String>[];
      final args = <Object?>[];

      for (final t in tokens.take(6)) {
        whereParts.add('c.text LIKE ?');
        args.add('%$t%');
      }

      rows = await db.rawQuery(
        '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.text,
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
      usedFts = false;
    }

    var usedVectorFallback = false;

    if (rows.isEmpty && onlyIndexed) {
      // Final fallback: small vector-only scan.
      //
      // This makes cross-lingual semantic search work even when text retrieval
      // returns no matches (e.g. Chinese query over English chunks).
      //
      // Keep the scan small to avoid battery/memory issues on mobile.
      final vectorLimit = (candidateLimit * 3).clamp(120, 360);

      rows = await db.rawQuery(
        '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.text,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ($indexedFilter)
ORDER BY COALESCE(b.updated_at, 0) DESC, c.id DESC
LIMIT ?
''',
        [vectorLimit],
      );

      if (rows.isNotEmpty) {
        usedVectorFallback = true;
      }
    }

    if (rows.isEmpty) {
      return AiSemanticSearchLibraryResult(
        ok: false,
        query: query,
        evidence: const [],
        usedFts: usedFts,
        usedVectorFallback: usedVectorFallback,
        message: onlyIndexed
            ? 'No indexed content matched. Build AI indexes from Library → AI Index.'
            : 'No content matched.',
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

    // Collect candidates.
    final candidates = <_Candidate>[];
    for (final r in rows) {
      final bookId = (r['book_id'] as num?)?.toInt() ?? 0;
      if (bookId <= 0) continue;

      final embJson = r['embedding_json']?.toString() ?? '[]';
      final vec = _tryParseVector(embJson);
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
        message: 'No valid embedding vectors found. Please rebuild indexes.',
      );
    }

    // Normalize BM25 into [0,1] (1 = best) when available.
    if (usedFts) {
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

    final selected = _selectWithMmr(candidates, k);

    final evidence = selected.map((c) {
      final r = c.row;
      final href = r['chapter_href']?.toString() ?? '';
      final title = (r['chapter_title']?.toString() ?? '').trim();
      final anchor = title.isEmpty ? href : title;

      String snippet;
      if (usedFts) {
        snippet = (r['snippet']?.toString() ?? '').trim();
      } else {
        snippet = '';
      }
      if (snippet.isEmpty) {
        final rawText = r['text']?.toString() ?? '';
        snippet =
            rawText.length <= 450 ? rawText : '${rawText.substring(0, 450)}…';
      }

      final jumpLink = PaperReaderReaderIntent(
        bookId: c.bookId,
        href: href,
      ).toUri().toString();

      return AiSemanticSearchLibraryEvidence(
        bookId: c.bookId,
        bookTitle: (titles[c.bookId] ?? '').trim(),
        href: href,
        anchor: anchor,
        snippet: snippet,
        jumpLink: jumpLink,
        score: c.hybridScore,
      );
    }).toList(growable: false);

    return AiSemanticSearchLibraryResult(
      ok: true,
      query: query,
      evidence: evidence,
      usedFts: usedFts,
      usedVectorFallback: usedVectorFallback,
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
      selected.add(best);
      remaining.remove(best);

      // Extra dedupe: avoid returning many chunks from the same chapter.
      remaining.removeWhere((c) {
        if (c.bookId != best!.bookId) return false;
        final h1 = c.row['chapter_href']?.toString() ?? '';
        final h2 = best!.row['chapter_href']?.toString() ?? '';
        return h1.isNotEmpty && h1 == h2;
      });
    }

    return selected;
  }

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return rows.isNotEmpty;
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

  List<double>? _tryParseVector(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      return decoded.map((x) => (x as num).toDouble()).toList(growable: false);
    } catch (_) {
      return null;
    }
  }
}

class _Candidate {
  _Candidate({
    required this.row,
    required this.bookId,
    required this.model,
    required this.vector,
    required this.vectorNorm,
    required this.vectorScore,
  });

  final Map<String, Object?> row;
  final int bookId;
  final String model;
  final List<double> vector;
  final double? vectorNorm;

  final double vectorScore;
  double? textScore;
  double hybridScore = 0;
}
