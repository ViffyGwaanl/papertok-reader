import 'dart:convert';

import 'package:crypto/crypto.dart';
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

class AiVec1VectorIndexAvailability {
  const AiVec1VectorIndexAvailability({
    required this.available,
    this.info,
    this.lastError,
  });

  final bool available;
  final String? info;
  final String? lastError;
}

class AiVec1VectorIndexBuildResult {
  const AiVec1VectorIndexBuildResult({
    required this.available,
    required this.tablesBuilt,
    required this.rowsWritten,
    this.totalGroups = 0,
    this.cancelled = false,
    this.lastError,
  });

  final bool available;
  final int tablesBuilt;
  final int rowsWritten;
  final int totalGroups;
  final bool cancelled;
  final String? lastError;
}

class AiVec1VectorIndexBuildProgress {
  const AiVec1VectorIndexBuildProgress({
    required this.done,
    required this.total,
    required this.rowsWritten,
  });

  final int done;
  final int total;
  final int rowsWritten;
}

class AiVec1VectorIndexStatus {
  const AiVec1VectorIndexStatus({
    required this.available,
    required this.totalGroups,
    required this.readyGroups,
    required this.nativeRowCount,
    required this.annRowCount,
    this.info,
    this.lastError,
  });

  final bool available;
  final int totalGroups;
  final int readyGroups;
  final int nativeRowCount;
  final int annRowCount;
  final String? info;
  final String? lastError;

  int get missingGroupCount =>
      (totalGroups - readyGroups).clamp(0, totalGroups);

  bool get canBuild => available && nativeRowCount > 0 && missingGroupCount > 0;
}

class AiVec1VectorIndexBuilder {
  const AiVec1VectorIndexBuilder();

  static const backendId = 'vec1-ann';

  static String tableNameFor({
    required String providerId,
    required String embeddingModel,
    required int embeddingDim,
  }) {
    final key = '$providerId\u001f$embeddingModel\u001f$embeddingDim';
    final digest = sha1.convert(utf8.encode(key)).toString().substring(0, 16);
    return 'ai_vec1_index_$digest';
  }

  Future<AiVec1VectorIndexAvailability> inspectAvailability(
    Database db,
  ) async {
    try {
      final rows = await db.rawQuery('SELECT vec1_info() AS info');
      return AiVec1VectorIndexAvailability(
        available: true,
        info: rows.isEmpty ? null : rows.first['info']?.toString(),
      );
    } catch (e) {
      return AiVec1VectorIndexAvailability(
        available: false,
        lastError: e.toString(),
      );
    }
  }

  Future<bool> isAvailable(Database db) async {
    return (await inspectAvailability(db)).available;
  }

  Future<AiVec1VectorIndexStatus> inspectBuildStatus(Database db) async {
    final availability = await inspectAvailability(db);
    if (!availability.available) {
      return AiVec1VectorIndexStatus(
        available: false,
        totalGroups: 0,
        readyGroups: 0,
        nativeRowCount: 0,
        annRowCount: 0,
        info: availability.info,
        lastError: availability.lastError,
      );
    }

    final groups = await db.rawQuery('''
SELECT provider_id, embedding_model, embedding_dim, COUNT(*) AS row_count
FROM ai_vector_index_rows
GROUP BY provider_id, embedding_model, embedding_dim
ORDER BY provider_id, embedding_model, embedding_dim
''');
    var readyGroups = 0;
    var nativeRowCount = 0;
    var annRowCount = 0;
    String? lastError;

    for (final group in groups) {
      final providerId = group['provider_id']?.toString() ?? '';
      final embeddingModel = group['embedding_model']?.toString() ?? '';
      final embeddingDim = (group['embedding_dim'] as num?)?.toInt() ?? 0;
      final groupRowCount = (group['row_count'] as num?)?.toInt() ?? 0;
      nativeRowCount += groupRowCount;
      if (embeddingDim <= 0 || groupRowCount <= 0) continue;
      final tableName = tableNameFor(
        providerId: providerId,
        embeddingModel: embeddingModel,
        embeddingDim: embeddingDim,
      );
      try {
        if (!await _tableExists(db, tableName)) continue;
        final tableRows = await db.rawQuery(
          'SELECT COUNT(*) AS row_count FROM $tableName',
        );
        final tableRowCount = tableRows.isEmpty
            ? 0
            : (tableRows.first['row_count'] as num?)?.toInt() ?? 0;
        annRowCount += tableRowCount;
        if (tableRowCount >= groupRowCount) {
          readyGroups += 1;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    return AiVec1VectorIndexStatus(
      available: true,
      totalGroups: groups.length,
      readyGroups: readyGroups,
      nativeRowCount: nativeRowCount,
      annRowCount: annRowCount,
      info: availability.info,
      lastError: lastError,
    );
  }

  Future<AiVec1VectorIndexBuildResult> rebuildFromNativeShadowRows(
    Database db, {
    bool Function()? shouldCancel,
    void Function(AiVec1VectorIndexBuildProgress progress)? onProgress,
  }) async {
    final availability = await inspectAvailability(db);
    if (!availability.available) {
      return AiVec1VectorIndexBuildResult(
        available: false,
        tablesBuilt: 0,
        rowsWritten: 0,
        lastError: availability.lastError,
      );
    }

    final groups = await db.rawQuery('''
SELECT provider_id, embedding_model, embedding_dim, COUNT(*) AS row_count
FROM ai_vector_index_rows
GROUP BY provider_id, embedding_model, embedding_dim
ORDER BY provider_id, embedding_model, embedding_dim
''');
    var done = 0;
    var tablesBuilt = 0;
    var rowsWritten = 0;
    var cancelled = false;

    for (final group in groups) {
      if (shouldCancel?.call() == true) {
        cancelled = true;
        break;
      }
      final providerId = group['provider_id']?.toString() ?? '';
      final embeddingModel = group['embedding_model']?.toString() ?? '';
      final embeddingDim = (group['embedding_dim'] as num?)?.toInt() ?? 0;
      if (embeddingDim <= 0) continue;
      final tableName = tableNameFor(
        providerId: providerId,
        embeddingModel: embeddingModel,
        embeddingDim: embeddingDim,
      );
      await db.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS $tableName '
        'USING vec1(embedding, chunk_id, book_id)',
      );
      await db.delete(tableName);

      final vectorRows = await db.rawQuery(
        '''
SELECT chunk_id, book_id, embedding_blob
FROM ai_vector_index_rows
WHERE COALESCE(provider_id, '') = ?
  AND COALESCE(embedding_model, '') = ?
  AND embedding_dim = ?
ORDER BY chunk_id ASC
''',
        [providerId, embeddingModel, embeddingDim],
      );
      var groupRowsWritten = 0;
      for (final row in vectorRows) {
        if (shouldCancel?.call() == true) {
          cancelled = true;
          break;
        }
        final chunkId = (row['chunk_id'] as num?)?.toInt();
        final bookId = (row['book_id'] as num?)?.toInt();
        final blob = row['embedding_blob'];
        if (chunkId == null || bookId == null || blob == null) continue;
        final inserted = await db.insert(
          tableName,
          {
            'rowid': chunkId,
            'embedding': blob,
            'chunk_id': chunkId,
            'book_id': bookId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (inserted != 0) {
          rowsWritten += 1;
          groupRowsWritten += 1;
        }
        if (shouldCancel?.call() == true) {
          cancelled = true;
          break;
        }
      }

      if (cancelled) {
        break;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'ai_vector_index_meta',
        {
          'id': '$backendId::$providerId::$embeddingModel::$embeddingDim',
          'backend': backendId,
          'provider_id': providerId,
          'embedding_model': embeddingModel,
          'embedding_dim': embeddingDim,
          'index_status': 'ready',
          'row_count': groupRowsWritten,
          'last_error': null,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      tablesBuilt += 1;
      done += 1;
      onProgress?.call(
        AiVec1VectorIndexBuildProgress(
          done: done,
          total: groups.length,
          rowsWritten: rowsWritten,
        ),
      );
    }

    return AiVec1VectorIndexBuildResult(
      available: true,
      tablesBuilt: tablesBuilt,
      rowsWritten: rowsWritten,
      totalGroups: groups.length,
      cancelled: cancelled,
    );
  }

  Future<bool> hasMissingIndexedBookVectors(
    Database db, {
    required String providerId,
    required String embeddingModel,
    required int embeddingDim,
  }) async {
    final tableName = tableNameFor(
      providerId: providerId,
      embeddingModel: embeddingModel,
      embeddingDim: embeddingDim,
    );
    if (!await _tableExists(db, tableName)) {
      return true;
    }
    try {
      final rows = await db.rawQuery(
        '''
SELECT 1
FROM ai_vector_index_rows v
JOIN ai_book_index b ON b.book_id = v.book_id
LEFT JOIN $tableName ann ON ann.chunk_id = v.chunk_id
WHERE COALESCE(v.provider_id, '') = ?
  AND COALESCE(v.embedding_model, '') = ?
  AND v.embedding_dim = ?
  AND b.chunk_count > 0
  AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
  AND ann.chunk_id IS NULL
LIMIT 1
''',
        [providerId, embeddingModel, embeddingDim],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = ? LIMIT 1",
        [tableName],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

class AiVectorIndexPurger {
  const AiVectorIndexPurger();

  Future<void> purgeBook(
    DatabaseExecutor db, {
    required int bookId,
  }) async {
    final groups = await db.rawQuery(
      '''
SELECT provider_id, embedding_model, embedding_dim
FROM ai_vector_index_rows
WHERE book_id = ?
GROUP BY provider_id, embedding_model, embedding_dim
ORDER BY provider_id, embedding_model, embedding_dim
''',
      [bookId],
    );

    await db.delete(
      'ai_vector_index_rows',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );

    for (final group in groups) {
      final key = _VectorMetaKey(
        providerId: group['provider_id']?.toString() ?? '',
        embeddingModel: group['embedding_model']?.toString() ?? '',
        embeddingDim: (group['embedding_dim'] as num?)?.toInt() ?? 0,
      );
      await _refreshNativeMeta(db, key);
      await _purgeVec1Group(db, key, bookId: bookId);
    }
  }

  Future<void> _refreshNativeMeta(
    DatabaseExecutor db,
    _VectorMetaKey key,
  ) async {
    final count = await _countRows(
      db,
      '''
SELECT COUNT(*) AS row_count
FROM ai_vector_index_rows
WHERE COALESCE(provider_id, '') = ?
  AND COALESCE(embedding_model, '') = ?
  AND embedding_dim = ?
''',
      [key.providerId, key.embeddingModel, key.embeddingDim],
    );
    if (count <= 0) {
      await _deleteMeta(db, AiNativeVectorIndexBuilder.backendId, key);
      return;
    }
    await _upsertMeta(
      db,
      backend: AiNativeVectorIndexBuilder.backendId,
      id: key.id,
      key: key,
      rowCount: count,
    );
  }

  Future<void> _purgeVec1Group(
    DatabaseExecutor db,
    _VectorMetaKey key, {
    required int bookId,
  }) async {
    if (key.embeddingDim <= 0) {
      await _deleteMeta(db, AiVec1VectorIndexBuilder.backendId, key);
      return;
    }
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: key.providerId,
      embeddingModel: key.embeddingModel,
      embeddingDim: key.embeddingDim,
    );
    if (!await _tableExists(db, tableName)) {
      await _deleteMeta(db, AiVec1VectorIndexBuilder.backendId, key);
      return;
    }

    try {
      await db.delete(tableName, where: 'book_id = ?', whereArgs: [bookId]);
      final count = await _countRows(
        db,
        'SELECT COUNT(*) AS row_count FROM $tableName',
        const [],
      );
      if (count <= 0) {
        await _deleteMeta(db, AiVec1VectorIndexBuilder.backendId, key);
        return;
      }
      await _upsertMeta(
        db,
        backend: AiVec1VectorIndexBuilder.backendId,
        id: '${AiVec1VectorIndexBuilder.backendId}::${key.providerId}::${key.embeddingModel}::${key.embeddingDim}',
        key: key,
        rowCount: count,
      );
    } catch (e) {
      await _markMetaError(
        db,
        backend: AiVec1VectorIndexBuilder.backendId,
        id: '${AiVec1VectorIndexBuilder.backendId}::${key.providerId}::${key.embeddingModel}::${key.embeddingDim}',
        key: key,
        error: e.toString(),
      );
    }
  }

  Future<int> _countRows(
    DatabaseExecutor db,
    String sql,
    List<Object?> args,
  ) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) return 0;
    return (rows.first['row_count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = ? LIMIT 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  Future<void> _deleteMeta(
    DatabaseExecutor db,
    String backend,
    _VectorMetaKey key,
  ) {
    return db.delete(
      'ai_vector_index_meta',
      where:
          'backend = ? AND COALESCE(provider_id, \'\') = ? AND COALESCE(embedding_model, \'\') = ? AND embedding_dim = ?',
      whereArgs: [
        backend,
        key.providerId,
        key.embeddingModel,
        key.embeddingDim
      ],
    );
  }

  Future<void> _upsertMeta(
    DatabaseExecutor db, {
    required String backend,
    required String id,
    required _VectorMetaKey key,
    required int rowCount,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _deleteMeta(db, backend, key);
    await db.insert(
      'ai_vector_index_meta',
      {
        'id': id,
        'backend': backend,
        'provider_id': key.providerId,
        'embedding_model': key.embeddingModel,
        'embedding_dim': key.embeddingDim,
        'index_status': 'ready',
        'row_count': rowCount,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _markMetaError(
    DatabaseExecutor db, {
    required String backend,
    required String id,
    required _VectorMetaKey key,
    required String error,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _deleteMeta(db, backend, key);
    await db.insert(
      'ai_vector_index_meta',
      {
        'id': id,
        'backend': backend,
        'provider_id': key.providerId,
        'embedding_model': key.embeddingModel,
        'embedding_dim': key.embeddingDim,
        'index_status': 'stale',
        'row_count': 0,
        'last_error': error,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class AiVec1VectorSearchBackend implements AiVectorSearchBackend {
  const AiVec1VectorSearchBackend();

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
    int? bookId,
  }) async {
    if (queryVector.isEmpty) return const [];
    if (bookId != null) {
      // The current Vec1 table is global per provider/model/dimension. Applying
      // a book filter after global ANN top-k can hide nearer rows inside the
      // requested book, so book-scoped recall must use the native/exact path
      // until a per-book or partition-aware ANN table exists.
      return const [];
    }
    const builder = AiVec1VectorIndexBuilder();
    if (!await builder.isAvailable(db)) return const [];

    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: providerId,
      embeddingModel: embeddingModel,
      embeddingDim: queryVector.length,
    );
    if (!await builder._tableExists(db, tableName)) return const [];

    final safeLimit = limit.clamp(1, 500);
    final queryBlob = AiVectorCodec.encodeFloat32(queryVector);
    final options = '{"k":$safeLimit}';
    final vectorRows = await db.rawQuery(
      '''
SELECT
  vv.chunk_id AS chunk_id,
  (1.0 - vv.distance) AS local_vector_score
FROM $tableName(?, ?) vv
JOIN ai_book_index b ON b.book_id = vv.book_id
WHERE (? = 0 OR (
  b.chunk_count > 0 AND COALESCE(b.index_status, 'succeeded') = 'succeeded'
))
  AND (? IS NULL OR vv.book_id = ?)
ORDER BY vv.distance ASC
LIMIT ?
''',
      [queryBlob, options, onlyIndexed ? 1 : 0, bookId, bookId, safeLimit],
    );
    final scoredByChunkId = <int, double>{};
    for (final row in vectorRows) {
      final chunkId = (row['chunk_id'] as num?)?.toInt();
      if (chunkId == null) continue;
      scoredByChunkId[chunkId] =
          (row['local_vector_score'] as num?)?.toDouble() ?? 0.0;
    }
    if (scoredByChunkId.isEmpty) return const [];

    final hydrated =
        await _hydrateVectorWinnerRows(db, scoredByChunkId.keys.toList());
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
    int? bookId,
  }) async {
    if (queryVector.isEmpty) return const [];
    if (bookId != null) {
      // vector_full_scan currently has no pre-scan book or row-budget guard.
      // Book-scoped callers need the bounded exact path until the native
      // adapter can prove partition-aware scanning.
      return const [];
    }
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
  AND (? IS NULL OR v.book_id = ?)
ORDER BY distance ASC
LIMIT ?
''',
      [
        queryBlob,
        providerId,
        embeddingModel,
        onlyIndexed ? 1 : 0,
        bookId,
        bookId,
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

    final hydrated =
        await _hydrateVectorWinnerRows(db, scoredByChunkId.keys.toList());
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
}

class AiAnnThenNativeThenExactVectorSearchBackend
    implements AiVectorSearchBackend {
  const AiAnnThenNativeThenExactVectorSearchBackend({
    this.annBackend = const AiVec1VectorSearchBackend(),
    this.nativeThenExactBackend = const AiNativeThenExactVectorSearchBackend(),
  });

  final AiVectorSearchBackend annBackend;
  final AiVectorSearchBackend nativeThenExactBackend;

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
    int? bookId,
  }) async {
    if (bookId != null) {
      return nativeThenExactBackend.searchRows(
        db,
        queryVector: queryVector,
        providerId: providerId,
        embeddingModel: embeddingModel,
        limit: limit,
        onlyIndexed: onlyIndexed,
        maxScanRows: maxScanRows,
        bookId: bookId,
      );
    }
    try {
      final annRows = await annBackend.searchRows(
        db,
        queryVector: queryVector,
        providerId: providerId,
        embeddingModel: embeddingModel,
        limit: limit,
        onlyIndexed: onlyIndexed,
        maxScanRows: maxScanRows,
        bookId: bookId,
      );
      if (annRows.isNotEmpty) {
        final hasMissingAnnRows =
            await const AiVec1VectorIndexBuilder().hasMissingIndexedBookVectors(
          db,
          providerId: providerId,
          embeddingModel: embeddingModel,
          embeddingDim: queryVector.length,
        );
        if (!hasMissingAnnRows) {
          return annRows;
        }
        final fallbackRows = await nativeThenExactBackend.searchRows(
          db,
          queryVector: queryVector,
          providerId: providerId,
          embeddingModel: embeddingModel,
          limit: limit,
          onlyIndexed: onlyIndexed,
          maxScanRows: maxScanRows,
          bookId: bookId,
        );
        return _mergeVectorRows(annRows, fallbackRows, limit: limit);
      }
    } catch (_) {
      // ANN extensions are optional and may be unavailable on a platform or
      // during migration; keep the stable native/exact path alive.
    }

    return nativeThenExactBackend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: limit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
      bookId: bookId,
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
    int? bookId,
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
        bookId: bookId,
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
          bookId: bookId,
        );
        return _mergeVectorRows(nativeRows, exactRows, limit: limit);
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
      bookId: bookId,
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
    int? bookId,
  }) {
    return exactBackend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: limit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
      bookId: bookId,
    );
  }
}

Future<List<Map<String, Object?>>> _hydrateVectorWinnerRows(
  Database db,
  List<int> chunkIds,
) {
  final ids = chunkIds.toSet().toList(growable: false);
  final placeholders = List.filled(ids.length, '?').join(',');
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
    ids,
  );
}

List<Map<String, Object?>> _mergeVectorRows(
  List<Map<String, Object?>> primaryRows,
  List<Map<String, Object?>> fallbackRows, {
  required int limit,
}) {
  final mergedById = <int, Map<String, Object?>>{};

  void addRows(List<Map<String, Object?>> rows) {
    for (final row in rows) {
      final chunkId = (row['chunk_id'] as num?)?.toInt();
      if (chunkId == null) continue;
      final existing = mergedById[chunkId];
      if (existing == null ||
          _scoreVectorRow(row).compareTo(_scoreVectorRow(existing)) > 0 ||
          (row['text'] != null && existing['text'] == null)) {
        mergedById[chunkId] = row;
      }
    }
  }

  addRows(primaryRows);
  addRows(fallbackRows);

  final safeLimit = limit.clamp(1, 500);
  final out = mergedById.values.toList(growable: false)
    ..sort((a, b) {
      final byScore = _scoreVectorRow(b).compareTo(_scoreVectorRow(a));
      if (byScore != 0) return byScore;
      final aId = (a['chunk_id'] as num?)?.toInt() ?? 0;
      final bId = (b['chunk_id'] as num?)?.toInt() ?? 0;
      return bId.compareTo(aId);
    });
  return out.take(safeLimit).toList(growable: false);
}

double _scoreVectorRow(Map<String, Object?> row) {
  return (row['local_vector_score'] as num?)?.toDouble() ?? 0.0;
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
