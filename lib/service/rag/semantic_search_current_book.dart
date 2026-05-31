import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
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
    this.message,
    this.indexInfo,
  });

  final bool ok;
  final int bookId;
  final String query;
  final List<AiSemanticSearchEvidence> evidence;
  final String? message;
  final AiBookIndexInfo? indexInfo;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'bookId': bookId,
        'query': query,
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
    int vectorScanYieldEvery = 32,
    @visibleForTesting AiCurrentBookVectorScanObserver? onVectorScanPage,
  })  : _db = database ?? AiIndexDatabase.instance,
        _embedQuery = embedQuery ?? _defaultEmbedQuery,
        _vectorScanPageSize = vectorScanPageSize.clamp(1, 512).toInt(),
        _vectorScanYieldEvery = vectorScanYieldEvery.clamp(1, 128).toInt(),
        _onVectorScanPage = onVectorScanPage;

  static final _globalSearchLock = _AsyncLock();

  final AiIndexDatabase _db;
  final AiCurrentBookQueryEmbedder _embedQuery;
  final int _vectorScanPageSize;
  final int _vectorScanYieldEvery;
  final AiCurrentBookVectorScanObserver? _onVectorScanPage;

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
  }) async {
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
    final qNorm = VectorMath.l2Norm(qVec);

    final db = await _db.database;
    final k = maxResults.clamp(1, 10);
    final scored = <({Map<String, Object?> row, double score})>[];
    var scannedRows = 0;
    var lastId = 0;
    var rowsSinceYield = 0;

    while (true) {
      final rows = await db.query(
        'ai_chunks',
        columns: [
          'id',
          'chapter_href',
          'chapter_title',
          'chunk_index',
          'embedding_input_hash',
          'context_version',
          'context_created_at',
          'embedding_blob',
          'embedding_norm',
        ],
        where: 'book_id = ? AND id > ?',
        whereArgs: [bookId, lastId],
        orderBy: 'id ASC',
        limit: _vectorScanPageSize,
      );
      if (rows.isEmpty) break;

      _onVectorScanPage?.call(rows);
      scannedRows += rows.length;
      lastId = (rows.last['id'] as num?)?.toInt() ?? lastId;

      final jsonById = await _embeddingJsonForRows(db, rows);

      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt();
        final v = AiVectorCodec.decodeVector(
          blob: r['embedding_blob'],
          jsonText: id == null ? null : jsonById[id],
        );
        if (v == null || v.isEmpty) continue;

        final norm = (r['embedding_norm'] as num?)?.toDouble();
        final score = VectorMath.cosineSimilarity(
          qVec,
          v,
          aNorm: qNorm,
          bNorm: norm,
        );
        _addScoredCandidate(scored, (row: r, score: score), k);

        rowsSinceYield++;
        if (rowsSinceYield >= _vectorScanYieldEvery) {
          rowsSinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Yield between pages so large current-book scans do not monopolize the
      // UI isolate while the reader is scrolling or paging.
      await Future<void>.delayed(Duration.zero);
    }

    if (scannedRows == 0) {
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
      indexInfo: info,
    );
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
    List<({Map<String, Object?> row, double score})> scored,
    ({Map<String, Object?> row, double score}) candidate,
    int limit,
  ) {
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
