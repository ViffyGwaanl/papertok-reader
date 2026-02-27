import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_index_database.dart';
import 'package:anx_reader/service/rag/ai_embeddings_service.dart';
import 'package:anx_reader/service/rag/vector_math.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef MemoryEmbedQueryFn = Future<List<double>> Function(
  String text, {
  required String model,
  String? providerId,
  int timeoutSeconds,
});

typedef MemoryEmbedDocumentsFn = Future<List<List<double>>> Function(
  List<String> texts, {
  required String model,
  String? providerId,
  int timeoutSeconds,
});

class MemorySearchService {
  MemorySearchService({
    MarkdownMemoryStore? store,
    MemoryIndexDatabase? indexDb,
    this.semanticEnabled = false,
    this.embeddingProviderId = '',
    this.embeddingModel = AiEmbeddingsService.defaultEmbeddingModel,
    this.embeddingsTimeoutSeconds = 60,
    this.hybridEnabled = true,
    this.vectorWeight = 0.7,
    this.textWeight = 0.3,
    this.candidateMultiplier = 4,
    this.mmrEnabled = false,
    this.mmrLambda = 0.7,
    this.temporalDecayEnabled = false,
    this.temporalDecayHalfLifeDays = 30,
    MemoryEmbedQueryFn? embedQuery,
    MemoryEmbedDocumentsFn? embedDocuments,
  })  : _store = store ?? MarkdownMemoryStore(),
        _indexDb = indexDb ?? MemoryIndexDatabase(),
        _embedQuery = embedQuery,
        _embedDocuments = embedDocuments;

  final MarkdownMemoryStore _store;
  final MemoryIndexDatabase _indexDb;

  final bool semanticEnabled;
  final String embeddingProviderId;
  final String embeddingModel;
  final int embeddingsTimeoutSeconds;

  /// Controls whether we mix BM25 keyword score into the final ranking.
  ///
  /// When disabled, we still use FTS (if available) to generate candidates,
  /// but the final score is vector-only.
  final bool hybridEnabled;

  /// Weight for vector similarity in hybrid ranking (0..1).
  final double vectorWeight;

  /// Weight for BM25-derived text score in hybrid ranking (0..1).
  final double textWeight;

  /// Candidate pool multiplier. Similar to OpenClaw's candidateMultiplier.
  final int candidateMultiplier;

  /// Whether to apply MMR re-ranking for diversity.
  final bool mmrEnabled;

  /// MMR lambda (0..1), higher = more relevance, lower = more diversity.
  final double mmrLambda;

  /// Whether to apply temporal decay to daily notes.
  final bool temporalDecayEnabled;

  /// Half-life (days) for temporal decay.
  final int temporalDecayHalfLifeDays;

  final MemoryEmbedQueryFn? _embedQuery;
  final MemoryEmbedDocumentsFn? _embedDocuments;

  static final RegExp _ftsSafeToken = RegExp(r'^[0-9A-Za-z_\u4e00-\u9fff]+$');

  String _escapeFtsToken(String token) {
    if (_ftsSafeToken.hasMatch(token)) return token;

    // Escape embedded quotes for FTS phrase syntax.
    final escaped = token.replaceAll('"', '""');
    return '"$escaped"';
  }

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
      if (s.length > 40) {
        out.add(s.substring(0, 40));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  String _buildFtsQuery(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return '';
    return tokens.take(12).map(_escapeFtsToken).join(' OR ');
  }

  Future<void> syncIndex() async {
    await _syncIndex();
  }

  Future<void> _syncIndex() async {
    await _store.ensureInitialized();

    final db = await _indexDb.database;

    // Collect target files.
    final targets = <File>[];
    targets.add(File(
        p.join(_store.rootDir.path, MarkdownMemoryStore.longTermFileName)));

    final dailyNames = await _store.listDailyFileNames(limit: 5000);
    for (final name in dailyNames) {
      targets.add(File(p.join(_store.rootDir.path, name)));
    }

    final seen = <String>{};

    // Load existing doc metadata.
    final existingRows =
        await db.query('memory_docs', columns: ['doc_id', 'mtime', 'size']);
    final existing = <String, ({int mtime, int size})>{};
    for (final r in existingRows) {
      final id = (r['doc_id'] ?? '').toString();
      final mtime = (r['mtime'] as num?)?.toInt() ?? 0;
      final size = (r['size'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty) {
        existing[id] = (mtime: mtime, size: size);
      }
    }

    // Update changed/new files.
    for (final file in targets) {
      final name = p.basename(file.path);
      final docId = name;
      seen.add(docId);

      if (!await file.exists()) continue;
      final stat = await file.stat();
      final mtime = stat.modified.millisecondsSinceEpoch;
      final size = stat.size;

      final prev = existing[docId];
      if (prev != null && prev.mtime == mtime && prev.size == size) {
        continue;
      }

      // Rebuild chunks for this doc.
      await db.transaction((txn) async {
        await txn
            .delete('memory_chunks', where: 'doc_id = ?', whereArgs: [docId]);

        final lines = await file.readAsLines();
        final chunks = _chunkLines(lines);
        var idx = 0;
        for (final c in chunks) {
          final hash = sha1.convert(utf8.encode(c.text)).toString();
          await txn.insert('memory_chunks', {
            'doc_id': docId,
            'chunk_index': idx++,
            'start_line': c.startLine,
            'end_line': c.endLine,
            'text': c.text,
            'content_hash': hash,
          });
        }

        final isLongTerm = name.toLowerCase() ==
            MarkdownMemoryStore.longTermFileName.toLowerCase();
        final date = isLongTerm ? null : name.replaceAll('.md', '');

        await txn.insert(
          'memory_docs',
          {
            'doc_id': docId,
            'file_name': name,
            'is_long_term': isLongTerm ? 1 : 0,
            'date': date,
            'mtime': mtime,
            'size': size,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    }

    // Delete missing docs.
    final missing = existing.keys.where((k) => !seen.contains(k)).toList();
    if (missing.isNotEmpty) {
      await db.transaction((txn) async {
        for (final id in missing) {
          await txn
              .delete('memory_chunks', where: 'doc_id = ?', whereArgs: [id]);
          await txn.delete('memory_docs', where: 'doc_id = ?', whereArgs: [id]);
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 20,
    bool includeLongTerm = true,
    bool includeDaily = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final capped = limit.clamp(1, 100);

    final useSemantic =
        semanticEnabled && embeddingProviderId.trim().isNotEmpty;

    try {
      await _store.ensureInitialized(ensureToday: false);
      final db = await _indexDb.database;

      // Do not block search on index refresh. If the index is empty (first run
      // or DB deleted), schedule a background rebuild and fallback to the raw
      // file scan for this request.
      try {
        final stats =
            await db.rawQuery('SELECT COUNT(*) AS c FROM memory_docs');
        final c = (stats.first['c'] as num?)?.toInt() ?? 0;
        if (c <= 0) {
          unawaited(syncIndex());
          return _store.search(
            q,
            limit: capped,
            includeLongTerm: includeLongTerm,
            includeDaily: includeDaily,
          );
        }
      } catch (_) {
        // If DB is not ready, fallback to raw search.
        unawaited(syncIndex());
        return _store.search(
          q,
          limit: capped,
          includeLongTerm: includeLongTerm,
          includeDaily: includeDaily,
        );
      }

      if (useSemantic) {
        await _ensureSemanticMeta(db);
      }

      // Check FTS availability.
      final ftsTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_chunks_fts'",
      );
      final hasFts = ftsTables.isNotEmpty;

      if (!hasFts) {
        if (useSemantic) {
          return _vectorOnlySearch(
            db,
            q,
            limit: capped,
            includeLongTerm: includeLongTerm,
            includeDaily: includeDaily,
          );
        }

        // No FTS: fallback.
        return _store.search(
          q,
          limit: capped,
          includeLongTerm: includeLongTerm,
          includeDaily: includeDaily,
        );
      }

      final ftsQuery = _buildFtsQuery(q);
      if (ftsQuery.isEmpty) {
        return const [];
      }

      final typeFilter = <String>[];
      if (!includeLongTerm) {
        typeFilter.add('d.is_long_term = 0');
      }
      if (!includeDaily) {
        typeFilter.add('d.is_long_term = 1');
      }

      final whereType =
          typeFilter.isEmpty ? '' : 'AND (${typeFilter.join(' AND ')})';

      final candidateLimit = (capped * candidateMultiplier).clamp(60, 600);

      final rows = await db.rawQuery(
        '''
SELECT
  c.id AS chunk_id,
  d.file_name,
  d.is_long_term AS is_long_term,
  d.date AS doc_date,
  c.start_line,
  c.end_line,
  c.text,
  c.embedding_json,
  c.embedding_norm,
  bm25(memory_chunks_fts) AS bm25,
  snippet(memory_chunks_fts, 0, '', '', '…', 18) AS snippet
FROM memory_chunks_fts
JOIN memory_chunks c ON c.id = memory_chunks_fts.rowid
JOIN memory_docs d ON d.doc_id = c.doc_id
WHERE memory_chunks_fts MATCH ?
  $whereType
ORDER BY bm25
LIMIT ?
''',
        [ftsQuery, candidateLimit],
      );

      if (!useSemantic) {
        return _rankTextOnly(rows, limit: capped);
      }

      if (rows.isEmpty) {
        return _vectorOnlySearch(
          db,
          q,
          limit: capped,
          includeLongTerm: includeLongTerm,
          includeDaily: includeDaily,
        );
      }

      return _semanticRerank(
        db,
        q,
        rows,
        limit: capped,
      );
    } catch (_) {
      // Best-effort fallback.
      return _store.search(
        q,
        limit: capped,
        includeLongTerm: includeLongTerm,
        includeDaily: includeDaily,
      );
    }
  }

  Future<void> _ensureSemanticMeta(Database db) async {
    final provider = embeddingProviderId.trim();
    final model = embeddingModel.trim().isEmpty
        ? AiEmbeddingsService.defaultEmbeddingModel
        : embeddingModel.trim();

    try {
      final rows = await db.query(
        'memory_index_meta',
        columns: ['key', 'value'],
        where: "key IN ('provider_id','embedding_model')",
      );

      final map = <String, String>{
        for (final r in rows)
          (r['key'] ?? '').toString(): (r['value'] ?? '').toString(),
      };

      final prevProvider = (map['provider_id'] ?? '').trim();
      final prevModel = (map['embedding_model'] ?? '').trim();

      if (prevProvider == provider && prevModel == model) {
        return;
      }

      // Config changed: clear all semantic cache to avoid mixing vectors.
      await db.execute('''
UPDATE memory_chunks
SET provider_id = NULL,
    embedding_model = NULL,
    embedding_json = NULL,
    embedding_dim = NULL,
    embedding_norm = NULL,
    embedded_at = NULL
''');

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'memory_index_meta',
        {
          'key': 'provider_id',
          'value': provider,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await db.insert(
        'memory_index_meta',
        {
          'key': 'embedding_model',
          'value': model,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Best-effort only.
    }
  }

  List<double>? _tryParseVector(Object? json) {
    if (json == null) return null;
    final s = json.toString().trim();
    if (s.isEmpty) return null;

    try {
      final decoded = jsonDecode(s);
      if (decoded is! List) return null;
      return decoded.map((x) => (x as num).toDouble()).toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureEmbeddingsForRows(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    final provider = embeddingProviderId.trim();
    if (provider.isEmpty) return;

    final model = embeddingModel.trim().isEmpty
        ? AiEmbeddingsService.defaultEmbeddingModel
        : embeddingModel.trim();

    final missing = <Map<String, Object?>>[];
    for (final r in rows) {
      final existing = (r['embedding_json'] ?? '').toString().trim();
      if (existing.isEmpty) {
        missing.add(r);
      }
    }

    if (missing.isEmpty) return;

    final fn = _embedDocuments;
    final embed = fn ?? AiEmbeddingsService.embedDocuments;

    const batchSize = 16;
    for (var offset = 0; offset < missing.length; offset += batchSize) {
      final batch =
          missing.skip(offset).take(batchSize).toList(growable: false);
      final texts = batch
          .map((r) => (r['text'] ?? '').toString())
          .toList(growable: false);

      final vectors = await embed(
        texts,
        model: model,
        providerId: provider,
        timeoutSeconds: embeddingsTimeoutSeconds,
      );

      for (var i = 0; i < batch.length; i++) {
        final r = batch[i];
        final v = vectors[i];
        final norm = VectorMath.l2Norm(v);
        final jsonStr = jsonEncode(v);

        final chunkId = (r['chunk_id'] as num?)?.toInt();
        if (chunkId == null) continue;

        await db.update(
          'memory_chunks',
          {
            'provider_id': provider,
            'embedding_model': model,
            'embedding_json': jsonStr,
            'embedding_dim': v.length,
            'embedding_norm': norm,
            'embedded_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [chunkId],
        );

        // Update in-memory row to avoid re-query.
        r['embedding_json'] = jsonStr;
        r['embedding_norm'] = norm;
      }
    }
  }

  double _bm25ToScore(double bm25) {
    // FTS5 bm25() is lower-is-better and can be negative.
    final v = bm25 < 0 ? 0.0 : bm25;
    return 1.0 / (1.0 + v);
  }

  DateTime? _tryParseDocDate(Object? raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    final parts = s.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  double _applyTemporalDecay(
    double score, {
    required bool isLongTerm,
    required DateTime? docDate,
  }) {
    if (!temporalDecayEnabled) return score;
    if (isLongTerm) return score;
    if (docDate == null) return score;

    final ageDays = DateTime.now().difference(docDate).inDays;
    if (ageDays <= 0) return score;

    final halfLife =
        temporalDecayHalfLifeDays <= 0 ? 30 : temporalDecayHalfLifeDays;

    final factor = pow(0.5, ageDays / halfLife);
    return score * factor;
  }

  Set<String> _tokenizeForMmr(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'''["'\[\]\(\)\{\}:;]+'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return const {};

    final raw = cleaned.split(' ');
    final out = <String>{};
    for (final t in raw) {
      final s = t.trim();
      if (s.isEmpty) continue;
      out.add(s.length > 40 ? s.substring(0, 40) : s);
      if (out.length >= 80) break;
    }
    return out;
  }

  double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    var inter = 0;
    for (final t in a) {
      if (b.contains(t)) inter++;
    }
    final union = a.length + b.length - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  List<({Map<String, Object?> row, double score, Set<String> tokens})>
      _selectWithMmr(
    List<({Map<String, Object?> row, double score, Set<String> tokens})> scored,
    int limit,
  ) {
    if (!mmrEnabled || scored.length <= limit) {
      return scored.take(limit).toList(growable: false);
    }

    final lambda = mmrLambda.clamp(0.0, 1.0);
    final selected =
        <({Map<String, Object?> row, double score, Set<String> tokens})>[];
    final remaining = List.of(scored);

    // Start with the most relevant.
    selected.add(remaining.removeAt(0));

    while (selected.length < limit && remaining.isNotEmpty) {
      var bestIdx = 0;
      var bestScore = double.negativeInfinity;

      for (var i = 0; i < remaining.length; i++) {
        final cand = remaining[i];

        var maxSim = 0.0;
        for (final s in selected) {
          final sim = _jaccard(cand.tokens, s.tokens);
          if (sim > maxSim) maxSim = sim;
          if (maxSim >= 1.0) break;
        }

        final mmrScore = lambda * cand.score - (1 - lambda) * maxSim;
        if (mmrScore > bestScore) {
          bestScore = mmrScore;
          bestIdx = i;
        }
      }

      selected.add(remaining.removeAt(bestIdx));
    }

    return selected;
  }

  List<Map<String, dynamic>> _rankTextOnly(
    List<Map<String, Object?>> rows, {
    required int limit,
  }) {
    final scored =
        <({Map<String, Object?> row, double score, Set<String> tokens})>[];

    for (final r in rows) {
      final bm25Raw = (r['bm25'] as num?)?.toDouble();
      final base = bm25Raw == null ? 0.0 : _bm25ToScore(bm25Raw);

      final isLongTerm = ((r['is_long_term'] as num?)?.toInt() ?? 0) == 1;
      final docDate = _tryParseDocDate(r['doc_date']);

      final score = _applyTemporalDecay(
        base,
        isLongTerm: isLongTerm,
        docDate: docDate,
      );

      final snippet = (r['snippet'] ?? '').toString();
      final text = snippet.trim().isNotEmpty
          ? snippet
          : (r['text'] ?? '').toString().trim().split('\n').first;

      scored.add((row: r, score: score, tokens: _tokenizeForMmr(text)));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final selected = _selectWithMmr(scored, limit);

    return selected.map((e) {
      final r = e.row;
      final file = (r['file_name'] ?? '').toString();
      final start = (r['start_line'] as num?)?.toInt();
      final end = (r['end_line'] as num?)?.toInt();
      final snippet = (r['snippet'] ?? '').toString();
      final text = snippet.trim().isNotEmpty
          ? snippet
          : (r['text'] ?? '').toString().trim().split('\n').first;

      return {
        'file': file,
        'line': start,
        if (end != null) 'endLine': end,
        'text': text,
      };
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _semanticRerank(
    Database db,
    String query,
    List<Map<String, Object?>> rows, {
    required int limit,
  }) async {
    await _ensureEmbeddingsForRows(db, rows);

    final provider = embeddingProviderId.trim();
    final model = embeddingModel.trim().isEmpty
        ? AiEmbeddingsService.defaultEmbeddingModel
        : embeddingModel.trim();

    final embedQ = _embedQuery ?? AiEmbeddingsService.embedQuery;
    final qVec = await embedQ(
      query,
      model: model,
      providerId: provider,
      timeoutSeconds: embeddingsTimeoutSeconds,
    );
    final qNorm = VectorMath.l2Norm(qVec);

    final scored =
        <({Map<String, Object?> row, double score, Set<String> tokens})>[];
    for (final r in rows) {
      final v = _tryParseVector(r['embedding_json']);
      if (v == null) continue;
      final vNorm = (r['embedding_norm'] as num?)?.toDouble();
      final vectorScore = VectorMath.cosineSimilarity(
        qVec,
        v,
        aNorm: qNorm,
        bNorm: vNorm,
      );

      final bm25Raw = (r['bm25'] as num?)?.toDouble();
      final textScore = bm25Raw == null ? 0.0 : _bm25ToScore(bm25Raw);

      var score = vectorScore;

      if (hybridEnabled) {
        var vW = vectorWeight;
        var tW = textWeight;
        final sum = vW + tW;
        if (sum > 0) {
          vW = vW / sum;
          tW = tW / sum;
        }
        score = vW * vectorScore + tW * textScore;
      }

      final isLongTerm = ((r['is_long_term'] as num?)?.toInt() ?? 0) == 1;
      final docDate = _tryParseDocDate(r['doc_date']);

      final finalScore = _applyTemporalDecay(
        score,
        isLongTerm: isLongTerm,
        docDate: docDate,
      );

      final snippet = (r['snippet'] ?? '').toString();
      final mmrText =
          snippet.trim().isNotEmpty ? snippet : (r['text'] ?? '').toString();

      scored.add((
        row: r,
        score: finalScore,
        tokens: _tokenizeForMmr(mmrText),
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final selected = _selectWithMmr(scored, limit);

    return selected.map((e) {
      final r = e.row;
      final file = (r['file_name'] ?? '').toString();
      final start = (r['start_line'] as num?)?.toInt();
      final end = (r['end_line'] as num?)?.toInt();
      final snippet = (r['snippet'] ?? '').toString();
      final text = snippet.trim().isNotEmpty
          ? snippet
          : (r['text'] ?? '').toString().trim().split('\n').first;

      return {
        'file': file,
        'line': start,
        if (end != null) 'endLine': end,
        'text': text,
      };
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _vectorOnlySearch(
    Database db,
    String query, {
    required int limit,
    required bool includeLongTerm,
    required bool includeDaily,
  }) async {
    final typeFilter = <String>[];
    if (!includeLongTerm) {
      typeFilter.add('d.is_long_term = 0');
    }
    if (!includeDaily) {
      typeFilter.add('d.is_long_term = 1');
    }
    final whereType =
        typeFilter.isEmpty ? '' : 'WHERE ${typeFilter.join(' AND ')}';

    final candidateLimit = (limit * candidateMultiplier * 3).clamp(80, 300);

    final rows = await db.rawQuery(
      '''
SELECT
  c.id AS chunk_id,
  d.file_name,
  d.is_long_term AS is_long_term,
  d.date AS doc_date,
  c.start_line,
  c.end_line,
  c.text,
  c.embedding_json,
  c.embedding_norm,
  NULL AS bm25,
  '' AS snippet
FROM memory_chunks c
JOIN memory_docs d ON d.doc_id = c.doc_id
$whereType
ORDER BY d.updated_at DESC, c.id DESC
LIMIT ?
''',
      [candidateLimit],
    );

    if (rows.isEmpty) return const [];

    return _semanticRerank(
      db,
      query,
      rows.cast<Map<String, Object?>>(),
      limit: limit,
    );
  }

  List<_Chunk> _chunkLines(List<String> lines) {
    final out = <_Chunk>[];

    // Group by paragraphs (blank lines separate).
    final buffer = StringBuffer();
    var currentStartLine = 1;

    void flush(int endLine) {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.isEmpty) return;

      // Split very long blocks.
      const maxChars = 2200;
      const overlap = 200;
      if (text.length <= maxChars) {
        out.add(
            _Chunk(text: text, startLine: currentStartLine, endLine: endLine));
        return;
      }

      var offset = 0;
      var idx = 0;
      while (offset < text.length) {
        final end = (offset + maxChars).clamp(0, text.length);
        final part = text.substring(offset, end).trim();
        if (part.isNotEmpty) {
          out.add(_Chunk(
            text: part,
            startLine: currentStartLine,
            endLine: endLine,
          ));
          idx++;
        }
        if (end >= text.length) break;
        offset = (end - overlap).clamp(0, text.length);
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNo = i + 1;

      if (line.trim().isEmpty) {
        flush(lineNo);
        currentStartLine = lineNo + 1;
        continue;
      }

      if (buffer.isEmpty) {
        currentStartLine = lineNo;
      }
      buffer.writeln(line);
    }

    flush(lines.length);

    // Safety: ensure at least one chunk for non-empty files.
    if (out.isEmpty) {
      final joined = lines.join('\n').trim();
      if (joined.isNotEmpty) {
        out.add(_Chunk(text: joined, startLine: 1, endLine: lines.length));
      }
    }

    return out;
  }
}

class _Chunk {
  _Chunk({required this.text, required this.startLine, required this.endLine});

  final String text;
  final int startLine;
  final int endLine;
}
