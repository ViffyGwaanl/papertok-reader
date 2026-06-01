import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:sqflite/sqflite.dart';

class AiNativeVectorBackfillResult {
  const AiNativeVectorBackfillResult({
    required this.rowsWritten,
    required this.rowsDeleted,
  });

  final int rowsWritten;
  final int rowsDeleted;
}

class AiNativeVectorIndexedBooksBackfillResult {
  const AiNativeVectorIndexedBooksBackfillResult({
    required this.booksProcessed,
    required this.rowsWritten,
    required this.rowsDeleted,
    this.totalCandidates = 0,
    this.cancelled = false,
  });

  final int booksProcessed;
  final int rowsWritten;
  final int rowsDeleted;
  final int totalCandidates;
  final bool cancelled;
}

class AiNativeVectorBackfillProgress {
  const AiNativeVectorBackfillProgress({
    required this.done,
    required this.total,
    required this.rowsWritten,
    required this.rowsDeleted,
  });

  final int done;
  final int total;
  final int rowsWritten;
  final int rowsDeleted;
}

class AiNativeVectorIndexStatus {
  const AiNativeVectorIndexStatus({
    required this.indexedBookCount,
    required this.readyBookCount,
    required this.shadowedBookCount,
    required this.vectorRowCount,
    required this.missingBookCount,
  });

  final int indexedBookCount;
  final int readyBookCount;
  final int shadowedBookCount;
  final int vectorRowCount;
  final int missingBookCount;

  bool get isComplete => indexedBookCount > 0 && missingBookCount == 0;
}

class AiNativeVectorIndexBuilder {
  const AiNativeVectorIndexBuilder();

  static const backendId = 'native-sql-shadow';

  Future<AiNativeVectorIndexedBooksBackfillResult> backfillIndexedBooks(
    Database db, {
    bool Function()? shouldCancel,
    void Function(AiNativeVectorBackfillProgress progress)? onProgress,
  }) async {
    final books = await db.rawQuery('''
SELECT book_id
FROM ai_book_index
WHERE chunk_count > 0
  AND COALESCE(index_status, 'succeeded') = 'succeeded'
ORDER BY book_id ASC
''');
    var booksProcessed = 0;
    var rowsWritten = 0;
    var rowsDeleted = 0;
    var cancelled = false;
    for (final book in books) {
      if (shouldCancel?.call() == true) {
        cancelled = true;
        break;
      }
      final bookId = (book['book_id'] as num?)?.toInt();
      if (bookId == null) continue;
      final result = await backfillBook(db, bookId: bookId);
      booksProcessed += 1;
      rowsWritten += result.rowsWritten;
      rowsDeleted += result.rowsDeleted;
      onProgress?.call(
        AiNativeVectorBackfillProgress(
          done: booksProcessed,
          total: books.length,
          rowsWritten: rowsWritten,
          rowsDeleted: rowsDeleted,
        ),
      );
    }
    return AiNativeVectorIndexedBooksBackfillResult(
      booksProcessed: booksProcessed,
      rowsWritten: rowsWritten,
      rowsDeleted: rowsDeleted,
      totalCandidates: books.length,
      cancelled: cancelled,
    );
  }

  Future<AiNativeVectorIndexStatus> inspectIndexedBooks(Database db) async {
    final indexedRows = await db.rawQuery('''
SELECT COUNT(*) AS book_count
FROM ai_book_index
WHERE chunk_count > 0
  AND COALESCE(index_status, 'succeeded') = 'succeeded'
''');
    final shadowRows = await db.rawQuery('''
SELECT COUNT(DISTINCT book_id) AS book_count, COUNT(*) AS row_count
FROM ai_vector_index_rows
''');
    final missingRows = await db.rawQuery('''
SELECT COUNT(DISTINCT c.book_id) AS book_count
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
LEFT JOIN ai_vector_index_rows v ON v.chunk_id = c.id
WHERE b.chunk_count > 0
  AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
  AND v.chunk_id IS NULL
  AND (
    c.embedding_blob IS NOT NULL
    OR COALESCE(c.embedding_json, '') != ''
  )
''');

    int readCount(List<Map<String, Object?>> rows, String key) {
      if (rows.isEmpty) return 0;
      return (rows.first[key] as num?)?.toInt() ?? 0;
    }

    final indexedBookCount = readCount(indexedRows, 'book_count');
    final missingBookCount = readCount(missingRows, 'book_count');

    return AiNativeVectorIndexStatus(
      indexedBookCount: indexedBookCount,
      readyBookCount:
          (indexedBookCount - missingBookCount).clamp(0, indexedBookCount),
      shadowedBookCount: readCount(shadowRows, 'book_count'),
      vectorRowCount: readCount(shadowRows, 'row_count'),
      missingBookCount: missingBookCount,
    );
  }

  Future<bool> hasMissingIndexedBookVectors(Database db) async {
    final rows = await db.rawQuery('''
SELECT 1
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
LEFT JOIN ai_vector_index_rows v ON v.chunk_id = c.id
WHERE b.chunk_count > 0
  AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
  AND v.chunk_id IS NULL
  AND (
    c.embedding_blob IS NOT NULL
    OR COALESCE(c.embedding_json, '') != ''
  )
LIMIT 1
''');
    return rows.isNotEmpty;
  }

  Future<AiNativeVectorBackfillResult> backfillBook(
    Database db, {
    required int bookId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var rowsWritten = 0;
    var rowsDeleted = 0;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'ai_vector_index_rows',
        columns: const ['chunk_id'],
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      final existingIds = existingRows
          .map((row) => (row['chunk_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();

      final rows = await txn.rawQuery(
        '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_dim,
  c.embedding_norm,
  COALESCE(b.provider_id, '') AS provider_id,
  COALESCE(b.embedding_model, '') AS embedding_model
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE c.book_id = ?
ORDER BY c.id ASC
''',
        [bookId],
      );

      final seenIds = <int>{};
      for (final row in rows) {
        final chunkId = (row['chunk_id'] as num?)?.toInt();
        if (chunkId == null) continue;
        final vector = AiVectorCodec.decodeVector(
          blob: row['embedding_blob'],
          jsonText: row['embedding_json']?.toString(),
        );
        if (vector == null || vector.isEmpty) continue;

        seenIds.add(chunkId);
        final providerId = row['provider_id']?.toString() ?? '';
        final embeddingModel = row['embedding_model']?.toString() ?? '';
        final dim = vector.length;

        final inserted = await txn.insert(
          'ai_vector_index_rows',
          {
            'chunk_id': chunkId,
            'book_id': bookId,
            'provider_id': providerId,
            'embedding_model': embeddingModel,
            'embedding_dim': dim,
            'embedding_blob': AiVectorCodec.encodeFloat32(vector),
            'embedding_norm': (row['embedding_norm'] as num?)?.toDouble(),
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (inserted != 0) rowsWritten += 1;
      }

      final staleIds = existingIds.difference(seenIds).toList(growable: false);
      if (staleIds.isNotEmpty) {
        final placeholders = List.filled(staleIds.length, '?').join(',');
        rowsDeleted += await txn.delete(
          'ai_vector_index_rows',
          where: 'chunk_id IN ($placeholders)',
          whereArgs: staleIds,
        );
      }

      final metaRows = await txn.rawQuery('''
SELECT provider_id, embedding_model, embedding_dim, COUNT(*) AS row_count
FROM ai_vector_index_rows
GROUP BY provider_id, embedding_model, embedding_dim
''');
      for (final row in metaRows) {
        final key = _VectorMetaKey(
          providerId: row['provider_id']?.toString() ?? '',
          embeddingModel: row['embedding_model']?.toString() ?? '',
          embeddingDim: (row['embedding_dim'] as num?)?.toInt() ?? 0,
        );
        final id = key.id;
        await txn.insert(
          'ai_vector_index_meta',
          {
            'id': id,
            'backend': backendId,
            'provider_id': key.providerId,
            'embedding_model': key.embeddingModel,
            'embedding_dim': key.embeddingDim,
            'index_status': 'ready',
            'row_count': (row['row_count'] as num?)?.toInt() ?? 0,
            'last_error': null,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    return AiNativeVectorBackfillResult(
      rowsWritten: rowsWritten,
      rowsDeleted: rowsDeleted,
    );
  }
}

class AiSqliteVectorSearchBackend implements AiVectorSearchBackend {
  const AiSqliteVectorSearchBackend();

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
  }) async {
    if (queryVector.isEmpty) return const [];
    if (!await _hasVectorFullScan(db)) return const [];
    final queryBlob = AiVectorCodec.encodeFloat32(queryVector);
    final safeLimit = limit.clamp(1, 500);
    final vectorRows = await db.rawQuery(
      '''
SELECT
  v.chunk_id AS chunk_id,
  (1.0 - distance) AS local_vector_score
FROM vector_full_scan('ai_vector_index_rows', 'embedding_blob', ?) vf
JOIN ai_vector_index_rows v ON v.rowid = vf.rowid
JOIN ai_book_index b ON b.book_id = v.book_id
WHERE COALESCE(v.provider_id, '') = ?
  AND COALESCE(v.embedding_model, '') = ?
  AND (? = 0 OR (
    b.chunk_count > 0 AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
  ))
ORDER BY distance ASC
LIMIT ?
''',
      [
        queryBlob,
        providerId,
        embeddingModel,
        onlyIndexed ? 1 : 0,
        safeLimit,
      ],
    );
    final scoredByChunkId = <int, double>{};
    for (final row in vectorRows) {
      final chunkId = (row['chunk_id'] as num?)?.toInt();
      if (chunkId == null) continue;
      scoredByChunkId[chunkId] =
          (row['local_vector_score'] as num?)?.toDouble() ?? 0.0;
    }
    if (scoredByChunkId.isEmpty) return const [];

    final hydrated = await _hydrateRows(db, scoredByChunkId.keys.toList());
    final hydratedById = <int, Map<String, Object?>>{
      for (final row in hydrated)
        if (row['chunk_id'] is num)
          (row['chunk_id'] as num).toInt(): Map<String, Object?>.from(row),
    };

    return [
      for (final entry in scoredByChunkId.entries)
        if (hydratedById[entry.key] != null)
          {
            ...hydratedById[entry.key]!,
            'local_vector_score': entry.value,
          }
    ];
  }

  Future<bool> _hasVectorFullScan(Database db) async {
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM pragma_function_list WHERE name = 'vector_full_scan' LIMIT 1",
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, Object?>>> _hydrateRows(
    Database db,
    List<int> chunkIds,
  ) {
    final placeholders = List.filled(chunkIds.length, '?').join(',');
    return db.rawQuery(
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
  c.embedding_input_hash,
  c.context_version,
  c.context_created_at,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  b.index_version
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE c.id IN ($placeholders)
''',
      chunkIds,
    );
  }
}

class AiNativeThenExactVectorSearchBackend implements AiVectorSearchBackend {
  const AiNativeThenExactVectorSearchBackend({
    this.nativeBackend = const AiSqliteVectorSearchBackend(),
    this.exactBackend = const AiExactVectorSearchBackend(),
  });

  final AiVectorSearchBackend nativeBackend;
  final AiVectorSearchBackend exactBackend;

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
  }) async {
    try {
      final nativeRows = await nativeBackend.searchRows(
        db,
        queryVector: queryVector,
        providerId: providerId,
        embeddingModel: embeddingModel,
        limit: limit,
        onlyIndexed: onlyIndexed,
        maxScanRows: maxScanRows,
      );
      if (nativeRows.isNotEmpty) {
        final hasMissingShadowRows = await const AiNativeVectorIndexBuilder()
            .hasMissingIndexedBookVectors(db);
        if (!hasMissingShadowRows) {
          return nativeRows;
        }
        final exactRows = await _searchExact(
          db,
          queryVector: queryVector,
          providerId: providerId,
          embeddingModel: embeddingModel,
          limit: limit,
          onlyIndexed: onlyIndexed,
          maxScanRows: maxScanRows,
        );
        return _mergeRows(nativeRows, exactRows, limit: limit);
      }
    } catch (_) {
      // Missing vector extension or uninitialized native index: fall back to
      // exact scan so retrieval keeps working on every supported platform.
    }

    return _searchExact(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: limit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
    );
  }

  Future<List<Map<String, Object?>>> _searchExact(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    required bool onlyIndexed,
    required int maxScanRows,
  }) {
    return exactBackend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: limit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
    );
  }

  List<Map<String, Object?>> _mergeRows(
    List<Map<String, Object?>> nativeRows,
    List<Map<String, Object?>> exactRows, {
    required int limit,
  }) {
    final mergedById = <int, Map<String, Object?>>{};

    void addRows(List<Map<String, Object?>> rows) {
      for (final row in rows) {
        final chunkId = (row['chunk_id'] as num?)?.toInt();
        if (chunkId == null) continue;
        final existing = mergedById[chunkId];
        if (existing == null ||
            _score(row).compareTo(_score(existing)) > 0 ||
            (row['text'] != null && existing['text'] == null)) {
          mergedById[chunkId] = row;
        }
      }
    }

    addRows(nativeRows);
    addRows(exactRows);

    final safeLimit = limit.clamp(1, 500);
    final out = mergedById.values.toList(growable: false)
      ..sort((a, b) {
        final byScore = _score(b).compareTo(_score(a));
        if (byScore != 0) return byScore;
        final aId = (a['chunk_id'] as num?)?.toInt() ?? 0;
        final bId = (b['chunk_id'] as num?)?.toInt() ?? 0;
        return bId.compareTo(aId);
      });
    return out.take(safeLimit).toList(growable: false);
  }

  double _score(Map<String, Object?> row) {
    return (row['local_vector_score'] as num?)?.toDouble() ?? 0.0;
  }
}

class _VectorMetaKey {
  const _VectorMetaKey({
    required this.providerId,
    required this.embeddingModel,
    required this.embeddingDim,
  });

  final String providerId;
  final String embeddingModel;
  final int embeddingDim;

  String get id => '$providerId::$embeddingModel::$embeddingDim';

  @override
  bool operator ==(Object other) {
    return other is _VectorMetaKey &&
        other.providerId == providerId &&
        other.embeddingModel == embeddingModel &&
        other.embeddingDim == embeddingDim;
  }

  @override
  int get hashCode => Object.hash(providerId, embeddingModel, embeddingDim);
}
