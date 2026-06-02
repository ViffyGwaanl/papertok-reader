import 'dart:async';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_local_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:papertok_reader/service/rag/source_ref_adapter.dart';
import 'package:papertok_reader/service/rag/vector_math.dart';
import 'package:sqflite/sqflite.dart';

typedef AiCurrentBookQueryEmbedder = Future<List<double>> Function(
  String text, {
  required String model,
  String? providerId,
});

typedef AiCurrentBookVectorScanObserver = void Function(
  List<Map<String, Object?>> rows,
);

typedef AiCurrentBookSearchProgressObserver = void Function(
  AiCurrentBookSearchProgress progress,
);

typedef AiCurrentBookVectorPageScorer
    = Future<List<AiCurrentBookVectorCandidate>> Function({
  required List<double> queryVector,
  required double queryNorm,
  required List<Map<String, Object?>> rows,
  required Map<int, String?> jsonById,
});

class AiCurrentBookSearchCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class AiCurrentBookSearchProgress {
  const AiCurrentBookSearchProgress({
    required this.scannedRows,
    required this.totalRows,
    this.cancelled = false,
  });

  final int scannedRows;
  final int totalRows;
  final bool cancelled;

  double get progress {
    if (totalRows <= 0) return 0;
    return (scannedRows / totalRows).clamp(0.0, 1.0).toDouble();
  }
}

class AiCurrentBookVectorCandidate {
  const AiCurrentBookVectorCandidate({
    required this.row,
    required this.score,
  });

  final Map<String, Object?> row;
  final double score;
}

class AiSemanticSearchEvidence {
  const AiSemanticSearchEvidence({
    required this.text,
    required this.href,
    required this.anchor,
    required this.jumpLink,
    required this.score,
    this.sourceRef,
  });

  final String text;
  final String href;
  final String anchor;

  /// Best-effort navigation deep link.
  ///
  /// This uses Paper Reader's app URL scheme.
  final String jumpLink;

  final double score;
  final SourceRef? sourceRef;

  Map<String, dynamic> toJson() => {
        'text': text,
        'href': href,
        'anchor': anchor,
        'jumpLink': jumpLink,
        'score': score,
        if (sourceRef != null) 'sourceRef': sourceRef!.toSafeJson(),
      };
}

class AiSemanticSearchResult {
  const AiSemanticSearchResult({
    required this.ok,
    required this.bookId,
    required this.query,
    required this.evidence,
    this.cancelled = false,
    this.message,
    this.indexInfo,
  });

  final bool ok;
  final int bookId;
  final String query;
  final List<AiSemanticSearchEvidence> evidence;
  final bool cancelled;
  final String? message;
  final AiBookIndexInfo? indexInfo;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'bookId': bookId,
        'query': query,
        if (cancelled) 'cancelled': true,
        if (message != null) 'message': message,
        if (indexInfo != null)
          'index': {
            'chunkCount': indexInfo!.chunkCount,
            'embeddingModel': indexInfo!.embeddingModel,
            'updatedAt': indexInfo!.updatedAt,
          },
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
      };
}

class SemanticSearchCurrentBook {
  SemanticSearchCurrentBook({
    AiIndexDatabase? database,
    AiCurrentBookQueryEmbedder? embedQuery,
    int vectorScanPageSize = 256,
    bool enableFtsCandidatePrefilter = true,
    int ftsCandidateLimit = 512,
    int? maxFallbackVectorRows,
    Duration progressMinInterval = const Duration(milliseconds: 160),
    AiVectorSearchBackend? vectorSearch,
    AiCurrentBookVectorPageScorer? scoreVectorPage,
    @visibleForTesting AiCurrentBookVectorScanObserver? onVectorScanPage,
    @visibleForTesting int Function()? nowMs,
  })  : _db = database ?? AiIndexDatabase.instance,
        _embedQuery = embedQuery ?? _defaultEmbedQuery,
        _vectorIndex = vectorSearch == null
            ? const AiLocalVectorIndex()
            : AiLocalVectorIndex(backend: vectorSearch),
        _vectorScanPageSize = vectorScanPageSize.clamp(1, 512).toInt(),
        _enableFtsCandidatePrefilter = enableFtsCandidatePrefilter,
        _ftsCandidateLimit = ftsCandidateLimit.clamp(1, 2048).toInt(),
        _maxFallbackVectorRows =
            maxFallbackVectorRows?.clamp(1, 1000000).toInt(),
        _progressMinInterval = progressMinInterval,
        _scoreVectorPage = scoreVectorPage ?? _defaultScoreVectorPage,
        _onVectorScanPage = onVectorScanPage,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const int foregroundFallbackVectorRowBudget = 1024;
  static const int toolFallbackVectorRowBudget = 2048;
  static final _globalSearchLock = _AsyncLock();
  static final RegExp _ftsSafeToken = RegExp(r'^[0-9A-Za-z_\u4e00-\u9fff]+$');
  static const List<String> _vectorRowColumns = [
    'id',
    'chapter_href',
    'chapter_title',
    'chunk_index',
    'embedding_input_hash',
    'context_version',
    'context_created_at',
    'embedding_blob',
    'embedding_norm',
  ];

  final AiIndexDatabase _db;
  final AiCurrentBookQueryEmbedder _embedQuery;
  final AiLocalVectorIndex _vectorIndex;
  final int _vectorScanPageSize;
  final bool _enableFtsCandidatePrefilter;
  final int _ftsCandidateLimit;
  final int? _maxFallbackVectorRows;
  final Duration _progressMinInterval;
  final AiCurrentBookVectorPageScorer _scoreVectorPage;
  final AiCurrentBookVectorScanObserver? _onVectorScanPage;
  final int Function() _nowMs;

  static Future<List<double>> _defaultEmbedQuery(
    String text, {
    required String model,
    String? providerId,
  }) {
    return AiEmbeddingsService.embedQuery(
      text,
      model: model,
      providerId: providerId,
    );
  }

  Future<AiSemanticSearchResult> search({
    required int bookId,
    required String query,
    int maxResults = 6,
    String? embeddingModel,
    String? providerId,
    AiCurrentBookSearchCancellationToken? cancelToken,
    AiCurrentBookSearchProgressObserver? onProgress,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message: 'query must not be empty',
      );
    }

    return _globalSearchLock.synchronized(
      () => _searchLocked(
        bookId: bookId,
        query: query,
        trimmedQuery: trimmed,
        maxResults: maxResults,
        embeddingModel: embeddingModel,
        providerId: providerId,
        cancelToken: cancelToken,
        onProgress: onProgress,
      ),
    );
  }

  Future<AiSemanticSearchResult> _searchLocked({
    required int bookId,
    required String query,
    required String trimmedQuery,
    required int maxResults,
    String? embeddingModel,
    String? providerId,
    AiCurrentBookSearchCancellationToken? cancelToken,
    AiCurrentBookSearchProgressObserver? onProgress,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return _cancelledResult(bookId: bookId, query: query);
    }

    final info = await _db.getBookIndexInfo(bookId);
    if (info == null || info.chunkCount <= 0) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message:
            'No semantic index found for this book. Build the index from Reading → Settings → Other → AI Index.',
        indexInfo: info,
      );
    }

    final effectiveModelRaw = (embeddingModel ??
            info.embeddingModel ??
            AiEmbeddingsService.defaultEmbeddingModel)
        .trim();
    final effectiveModel = effectiveModelRaw.isEmpty
        ? AiEmbeddingsService.defaultEmbeddingModel
        : effectiveModelRaw;

    final effectiveProviderId = (providerId ?? info.providerId ?? '').trim();

    final qVec = await _embedQuery(
      trimmedQuery,
      model: effectiveModel,
      providerId: effectiveProviderId.isEmpty ? null : effectiveProviderId,
    );
    if (cancelToken?.isCancelled ?? false) {
      _emitProgress(
        onProgress: onProgress,
        scannedRows: 0,
        totalRows: info.chunkCount,
        cancelled: true,
      );
      return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
    }
    final qNorm = VectorMath.l2Norm(qVec);

    final db = await _db.database;
    final k = maxResults.clamp(1, 10);
    final scored = <AiCurrentBookVectorCandidate>[];
    var scannedRows = 0;
    final backendRows = await _loadVectorBackendRows(
      db,
      bookId: bookId,
      queryVector: qVec,
      providerId: effectiveProviderId,
      embeddingModel: effectiveModel,
      limit: (k * 24).clamp(24, 120),
      maxScanRows: _fallbackTotalRows(info.chunkCount),
    );
    for (final row in backendRows) {
      _addScoredCandidate(
        scored,
        AiCurrentBookVectorCandidate(
          row: row,
          score: _vectorBackendScore(
            row,
            queryVector: qVec,
            queryNorm: qNorm,
          ),
        ),
        k,
      );
    }
    final ftsCandidateIds = _enableFtsCandidatePrefilter
        ? await _loadFtsCandidateIds(
            db,
            bookId: bookId,
            query: trimmedQuery,
            limit: _ftsCandidateLimit,
          )
        : null;
    final candidateIds = (ftsCandidateIds != null && ftsCandidateIds.isNotEmpty)
        ? ftsCandidateIds
        : null;
    final fallbackTotalRows = _fallbackTotalRows(info.chunkCount);
    var totalRows = candidateIds?.length ?? fallbackTotalRows;
    var fallbackScanLimited = false;
    int? lastProgressEmitMs;
    int? lastProgressScannedRows;
    bool lastProgressCancelled = false;

    void emitProgress({
      required int scannedRows,
      required int totalRows,
      bool cancelled = false,
      bool force = false,
    }) {
      if (onProgress == null) return;
      final now = _nowMs();
      final intervalMs = _progressMinInterval.inMilliseconds;
      final shouldEmit = force ||
          cancelled ||
          lastProgressEmitMs == null ||
          intervalMs <= 0 ||
          now - lastProgressEmitMs! >= intervalMs;
      if (!shouldEmit) return;
      if (lastProgressScannedRows == scannedRows &&
          lastProgressCancelled == cancelled) {
        return;
      }
      lastProgressEmitMs = now;
      lastProgressScannedRows = scannedRows;
      lastProgressCancelled = cancelled;
      _emitProgress(
        onProgress: onProgress,
        scannedRows: scannedRows,
        totalRows: totalRows,
        cancelled: cancelled,
      );
    }

    if (cancelToken?.isCancelled ?? false) {
      emitProgress(
        scannedRows: scannedRows,
        totalRows: totalRows,
        cancelled: true,
        force: true,
      );
      return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
    }

    Future<AiSemanticSearchResult?> scorePage(
      List<Map<String, Object?>> rows,
    ) async {
      if (rows.isEmpty) return null;
      if (cancelToken?.isCancelled ?? false) {
        emitProgress(
          scannedRows: scannedRows,
          totalRows: totalRows,
          cancelled: true,
          force: true,
        );
        return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
      }

      _onVectorScanPage?.call(rows);
      scannedRows += rows.length;
      emitProgress(
        scannedRows: scannedRows,
        totalRows: totalRows,
      );
      if (cancelToken?.isCancelled ?? false) {
        emitProgress(
          scannedRows: scannedRows,
          totalRows: totalRows,
          cancelled: true,
          force: true,
        );
        return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
      }

      final jsonById = await _embeddingJsonForRows(db, rows);
      if (cancelToken?.isCancelled ?? false) {
        emitProgress(
          scannedRows: scannedRows,
          totalRows: totalRows,
          cancelled: true,
          force: true,
        );
        return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
      }

      final pageCandidates = await _scoreVectorPage(
        queryVector: qVec,
        queryNorm: qNorm,
        rows: rows,
        jsonById: jsonById,
      );
      if (cancelToken?.isCancelled ?? false) {
        emitProgress(
          scannedRows: scannedRows,
          totalRows: totalRows,
          cancelled: true,
          force: true,
        );
        return _cancelledResult(bookId: bookId, query: query, indexInfo: info);
      }

      for (final candidate in pageCandidates) {
        _addScoredCandidate(scored, candidate, k);
      }

      // Yield between pages so large current-book scans do not monopolize the
      // UI isolate while the reader is scrolling or paging.
      await Future<void>.delayed(Duration.zero);
      return null;
    }

    Future<AiSemanticSearchResult?> scanFullBook() async {
      var lastId = 0;
      var remainingRows = _maxFallbackVectorRows;
      while (true) {
        final pageLimit = remainingRows == null
            ? _vectorScanPageSize
            : remainingRows < _vectorScanPageSize
                ? remainingRows
                : _vectorScanPageSize;
        if (pageLimit <= 0) {
          fallbackScanLimited = info.chunkCount > scannedRows;
          break;
        }
        final rows = await db.query(
          'ai_chunks',
          columns: _vectorRowColumns,
          where: 'book_id = ? AND id > ?',
          whereArgs: [bookId, lastId],
          orderBy: 'id ASC',
          limit: pageLimit,
        );
        if (rows.isEmpty) break;
        lastId = (rows.last['id'] as num?)?.toInt() ?? lastId;
        final cancelled = await scorePage(rows);
        if (cancelled != null) return cancelled;
        if (remainingRows != null) {
          remainingRows -= rows.length;
          if (remainingRows <= 0) {
            fallbackScanLimited = info.chunkCount > scannedRows;
            break;
          }
        }
      }
      return null;
    }

    if (candidateIds != null) {
      for (var offset = 0; offset < candidateIds.length;) {
        final end = (offset + _vectorScanPageSize) > candidateIds.length
            ? candidateIds.length
            : offset + _vectorScanPageSize;
        final pageIds = candidateIds.sublist(offset, end);
        offset = end;
        final cancelled = await scorePage(
          await _loadVectorRowsByIds(
            db,
            bookId: bookId,
            ids: pageIds,
          ),
        );
        if (cancelled != null) return cancelled;
      }

      if (scannedRows == 0 && scored.isEmpty) {
        totalRows = fallbackTotalRows;
        final cancelled = await scanFullBook();
        if (cancelled != null) return cancelled;
      }
    } else {
      if (scored.isEmpty) {
        final cancelled = await scanFullBook();
        if (cancelled != null) return cancelled;
      }
    }

    emitProgress(
      scannedRows: scannedRows,
      totalRows: totalRows,
      force: true,
    );

    if (scored.isEmpty && scannedRows == 0) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message:
            'Index metadata exists but chunk table is empty. Please rebuild the index.',
        indexInfo: info,
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.toList(growable: false);
    final textById = await _loadChunkTextById(
      top
          .map((it) => (it.row['id'] as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false),
    );

    final evidence = top.map((it) {
      final r = it.row;
      final rowId = (r['id'] as num?)?.toInt();
      final href = r['chapter_href']?.toString() ?? '';
      final title = (r['chapter_title']?.toString() ?? '').trim();
      final anchor = title.isEmpty ? href : title;

      final textRow = textById[rowId];
      final rawText =
          (textRow?['raw_text']?.toString().trim().isNotEmpty ?? false)
              ? textRow!['raw_text']!.toString()
              : textRow?['text']?.toString() ?? '';
      final snippet =
          rawText.length <= 450 ? rawText : '${rawText.substring(0, 450)}…';

      // Best-effort: we currently only have href, not per-chunk CFI.
      final jumpLink = PaperReaderReaderIntent(
        bookId: bookId,
        href: href,
      ).toUri().toString();
      final sourceRef = RagSourceRefAdapter.currentBook(
        bookId: bookId,
        href: href,
        text: snippet,
        anchor: anchor,
        jumpLink: jumpLink,
        chunkId: rowId,
        sourceHash: r['embedding_input_hash']?.toString(),
        providerId: effectiveProviderId,
        model: effectiveModel,
        indexVersion: info.indexVersion,
        contextVersion: (r['context_version'] as num?)?.toInt(),
        createdAt: (r['context_created_at'] as num?)?.toInt() ??
            info.updatedAt ??
            info.createdAt,
        confidence: it.score,
      );

      return AiSemanticSearchEvidence(
        text: snippet,
        href: href,
        anchor: anchor,
        jumpLink: jumpLink,
        score: it.score,
        sourceRef: sourceRef,
      );
    }).toList(growable: false);

    return AiSemanticSearchResult(
      ok: true,
      bookId: bookId,
      query: query,
      evidence: evidence,
      message: fallbackScanLimited
          ? 'Semantic search limited fallback vector scan to $scannedRows of ${info.chunkCount} chunks for device resources. Try a more specific keyword or rebuild the index.'
          : null,
      indexInfo: info,
    );
  }

  int _fallbackTotalRows(int chunkCount) {
    final limit = _maxFallbackVectorRows;
    if (limit == null || chunkCount <= limit) return chunkCount;
    return limit;
  }

  Future<List<Map<String, Object?>>> _loadVectorBackendRows(
    Database db, {
    required int bookId,
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    required int maxScanRows,
  }) async {
    if (queryVector.isEmpty || limit <= 0) return const [];
    try {
      final rows = await _vectorIndex.searchRows(
        db,
        queryVector: queryVector,
        providerId: providerId,
        embeddingModel: embeddingModel,
        limit: limit,
        onlyIndexed: true,
        maxScanRows: maxScanRows,
        bookId: bookId,
      );
      return rows
          .where((row) => (row['book_id'] as num?)?.toInt() == bookId)
          .map(_normalizeVectorBackendRow)
          .where((row) => (row['id'] as num?)?.toInt() != null)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, Object?> _normalizeVectorBackendRow(Map<String, Object?> row) {
    final out = Map<String, Object?>.from(row);
    out['id'] ??= out['chunk_id'];
    return out;
  }

  double _vectorBackendScore(
    Map<String, Object?> row, {
    required List<double> queryVector,
    required double queryNorm,
  }) {
    final backendScore = (row['local_vector_score'] as num?)?.toDouble();
    if (backendScore != null && backendScore.isFinite) {
      return backendScore.clamp(0.0, 1.0).toDouble();
    }
    final vector = AiVectorCodec.decodeVector(
      blob: row['embedding_blob'],
      jsonText: row['embedding_json']?.toString(),
    );
    if (vector == null || vector.isEmpty) return 0;
    final score = VectorMath.cosineSimilarity(
      queryVector,
      vector,
      aNorm: queryNorm,
      bNorm: (row['embedding_norm'] as num?)?.toDouble(),
    );
    return ((score + 1) / 2).clamp(0.0, 1.0).toDouble();
  }

  Future<List<int>?> _loadFtsCandidateIds(
    Database db, {
    required int bookId,
    required String query,
    required int limit,
  }) async {
    final match = _buildFtsQuery(query);
    if (match.isEmpty) return null;

    final hasFts = await _tableExists(db, 'ai_chunks_fts');
    if (!hasFts) return null;

    try {
      final rows = await db.rawQuery(
        '''
SELECT rowid
FROM ai_chunks_fts
WHERE ai_chunks_fts MATCH ?
  AND book_id = ?
ORDER BY bm25(ai_chunks_fts)
LIMIT ?
''',
        [match, bookId, limit],
      );
      final ids = <int>[];
      final seen = <int>{};
      for (final row in rows) {
        final id = (row['rowid'] as num?)?.toInt();
        if (id == null || id <= 0 || !seen.add(id)) continue;
        ids.add(id);
      }
      return ids;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> _loadVectorRowsByIds(
    Database db, {
    required int bookId,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.query(
      'ai_chunks',
      columns: _vectorRowColumns,
      where: 'book_id = ? AND id IN ($placeholders)',
      whereArgs: [bookId, ...ids],
      orderBy: 'id ASC',
    );
  }

  String _buildFtsQuery(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return '';
    return tokens.take(8).map(_escapeFtsToken).join(' OR ');
  }

  String _escapeFtsToken(String token) {
    if (_ftsSafeToken.hasMatch(token)) {
      return token;
    }
    final escaped = token.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<String> _tokenize(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'''["'\[\]\(\)\{\}:;]+'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];

    final out = <String>[];
    for (final raw in cleaned.split(' ')) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      out.add(token.length > 40 ? token.substring(0, 40) : token);
    }
    return out;
  }

  Future<Map<int, String?>> _embeddingJsonForRows(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    final ids = rows
        .where((row) => row['embedding_blob'] == null)
        .map((row) => (row['id'] as num?)?.toInt())
        .whereType<int>()
        .toList(growable: false);
    if (ids.isEmpty) {
      return const {};
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    final jsonRows = await db.query(
      'ai_chunks',
      columns: const ['id', 'embedding_json'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return {
      for (final row in jsonRows)
        if ((row['id'] as num?)?.toInt() case final id?)
          id: row['embedding_json']?.toString(),
    };
  }

  Future<Map<int, Map<String, Object?>>> _loadChunkTextById(
    List<int> ids,
  ) async {
    if (ids.isEmpty) {
      return const {};
    }
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'ai_chunks',
      columns: const ['id', 'text', 'raw_text'],
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return {
      for (final row in rows)
        if ((row['id'] as num?)?.toInt() case final id?) id: row,
    };
  }

  void _addScoredCandidate(
    List<AiCurrentBookVectorCandidate> scored,
    AiCurrentBookVectorCandidate candidate,
    int limit,
  ) {
    final candidateId = _candidateChunkId(candidate);
    if (candidateId != null) {
      for (var i = 0; i < scored.length; i++) {
        if (_candidateChunkId(scored[i]) != candidateId) continue;
        if (candidate.score > scored[i].score) {
          scored[i] = candidate;
        }
        return;
      }
    }
    if (scored.length < limit) {
      scored.add(candidate);
      return;
    }
    var minIndex = 0;
    var minScore = scored.first.score;
    for (var i = 1; i < scored.length; i++) {
      if (scored[i].score < minScore) {
        minIndex = i;
        minScore = scored[i].score;
      }
    }
    if (candidate.score > minScore) {
      scored[minIndex] = candidate;
    }
  }

  int? _candidateChunkId(AiCurrentBookVectorCandidate candidate) {
    return (candidate.row['id'] as num?)?.toInt() ??
        (candidate.row['chunk_id'] as num?)?.toInt();
  }

  AiSemanticSearchResult _cancelledResult({
    required int bookId,
    required String query,
    AiBookIndexInfo? indexInfo,
  }) {
    return AiSemanticSearchResult(
      ok: false,
      bookId: bookId,
      query: query,
      evidence: const [],
      cancelled: true,
      message: 'Semantic search cancelled.',
      indexInfo: indexInfo,
    );
  }

  void _emitProgress({
    required AiCurrentBookSearchProgressObserver? onProgress,
    required int scannedRows,
    required int totalRows,
    bool cancelled = false,
  }) {
    onProgress?.call(
      AiCurrentBookSearchProgress(
        scannedRows: scannedRows,
        totalRows: totalRows,
        cancelled: cancelled,
      ),
    );
  }
}

Future<List<AiCurrentBookVectorCandidate>> _defaultScoreVectorPage({
  required List<double> queryVector,
  required double queryNorm,
  required List<Map<String, Object?>> rows,
  required Map<int, String?> jsonById,
}) async {
  final encoded = await compute(
    _scoreCurrentBookVectorPage,
    <String, Object?>{
      'queryVector': queryVector,
      'queryNorm': queryNorm,
      'rows': rows,
      'jsonById': {
        for (final entry in jsonById.entries) entry.key.toString(): entry.value,
      },
    },
  );
  return encoded
      .map(
        (item) => AiCurrentBookVectorCandidate(
          row: Map<String, Object?>.from(item['row'] as Map),
          score: (item['score'] as num).toDouble(),
        ),
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _scoreCurrentBookVectorPage(
  Map<String, Object?> input,
) {
  final queryVector = ((input['queryVector'] as List?) ?? const [])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList(growable: false);
  final queryNorm = (input['queryNorm'] as num?)?.toDouble();
  final rows = ((input['rows'] as List?) ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);
  final jsonById = Map<String, Object?>.from(
    (input['jsonById'] as Map?) ?? const {},
  );

  final out = <Map<String, Object?>>[];
  for (final row in rows) {
    final id = (row['id'] as num?)?.toInt();
    final vector = AiVectorCodec.decodeVector(
      blob: row['embedding_blob'],
      jsonText: id == null ? null : jsonById[id.toString()]?.toString(),
    );
    if (vector == null || vector.isEmpty) continue;

    final norm = (row['embedding_norm'] as num?)?.toDouble();
    final score = VectorMath.cosineSimilarity(
      queryVector,
      vector,
      aNorm: queryNorm,
      bNorm: norm,
    );
    out.add(
      {
        'row': {
          'id': row['id'],
          'chapter_href': row['chapter_href'],
          'chapter_title': row['chapter_title'],
          'chunk_index': row['chunk_index'],
          'embedding_input_hash': row['embedding_input_hash'],
          'context_version': row['context_version'],
          'context_created_at': row['context_created_at'],
        },
        'score': score,
      },
    );
  }
  return out;
}

class _AsyncLock {
  Future<void> _tail = Future.value();

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = previous.then((_) => completer.future);

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
