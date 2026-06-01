import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('backfillBook converts old JSON vectors into native shadow rows',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1);
    final blobChunkId = await _insertChunk(
      db,
      bookId: 1,
      href: 'blob.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    final jsonChunkId = await _insertChunk(
      db,
      bookId: 1,
      href: 'json.xhtml',
      vector: const [0, 1],
      writeBlob: false,
    );
    final staleChunkId = await _insertInvalidChunk(
      db,
      bookId: 1,
      href: 'stale.xhtml',
    );
    await db.insert('ai_vector_index_rows', {
      'chunk_id': staleChunkId,
      'book_id': 1,
      'provider_id': 'stale',
      'embedding_model': 'stale',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [0, 0]),
      'created_at': 1,
      'updated_at': 1,
    });

    final result = await AiNativeVectorIndexBuilder().backfillBook(
      db,
      bookId: 1,
    );

    expect(result.rowsWritten, 2);
    expect(result.rowsDeleted, 1);
    final rows = await db.query(
      'ai_vector_index_rows',
      orderBy: 'chunk_id ASC',
    );
    expect(rows.map((r) => r['chunk_id']).toList(), [
      blobChunkId,
      jsonChunkId,
    ]);
    expect(rows.every((r) => r['provider_id'] == 'provider-a'), true);
    expect(rows.every((r) => r['embedding_model'] == 'model-a'), true);
    final jsonVector = AiVectorCodec.decodeFloat32(rows.last['embedding_blob']);
    expect(jsonVector, const [0, 1]);

    final metaRows = await db.query('ai_vector_index_meta');
    expect(metaRows, hasLength(1));
    expect(metaRows.single['backend'], 'native-sql-shadow');
    expect(metaRows.single['row_count'], 2);
    expect(metaRows.single['index_status'], 'ready');
  });

  test(
      'sqlite vector backend uses native vector_full_scan and hydrates winners',
      () async {
    final db = _RecordingNativeVectorDatabase(
      vectorRows: [
        {'chunk_id': 42, 'local_vector_score': 0.99},
      ],
      hydratedRows: [
        {
          'chunk_id': 42,
          'book_id': 1,
          'chapter_href': 'native.xhtml',
          'chapter_title': 'Native',
          'chunk_index': 0,
          'start_char': 0,
          'end_char': 11,
          'text': 'native text',
          'raw_text': 'native text',
          'context_text': 'native text',
          'embedding_input_hash': 'hash',
          'context_version': 0,
          'context_created_at': 0,
          'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
          'embedding_json': '[1,0]',
          'embedding_norm': 1.0,
          'embedding_model': 'model-a',
          'provider_id': 'provider-a',
          'index_version': 12,
        }
      ],
    );

    final backend = AiSqliteVectorSearchBackend();
    final hits = await backend.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(hits, hasLength(1));
    expect(hits.single['chapter_href'], 'native.xhtml');
    expect(hits.single['local_vector_score'], 0.99);
    expect(db.sqlLog[1], contains('vector_full_scan'));
    expect(db.sqlLog[1], contains('ai_vector_index_rows'));
    expect(db.sqlLog.last, contains('ai_chunks'));
    expect(db.argsLog.last, contains(42));
  });

  test('backfillIndexedBooks processes succeeded old chunk indexes', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1);
    await _insertBook(db, 2);
    await _insertBook(db, 3, status: 'failed');
    await _insertChunk(
      db,
      bookId: 1,
      href: 'book-one.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    await _insertChunk(
      db,
      bookId: 2,
      href: 'book-two.xhtml',
      vector: const [0, 1],
      writeBlob: false,
    );
    await _insertChunk(
      db,
      bookId: 3,
      href: 'failed-book.xhtml',
      vector: const [1, 1],
      writeBlob: true,
    );

    final result = await AiNativeVectorIndexBuilder().backfillIndexedBooks(db);

    expect(result.booksProcessed, 2);
    expect(result.rowsWritten, 2);
    final rows = await db.query(
      'ai_vector_index_rows',
      orderBy: 'book_id ASC',
    );
    expect(rows.map((r) => r['book_id']).toList(), [1, 2]);
  });

  test('backfillIndexedBooks can cancel between books and reports progress',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1);
    await _insertBook(db, 2);
    await _insertChunk(
      db,
      bookId: 1,
      href: 'book-one.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    await _insertChunk(
      db,
      bookId: 2,
      href: 'book-two.xhtml',
      vector: const [0, 1],
      writeBlob: true,
    );

    final progress = <AiNativeVectorBackfillProgress>[];
    final result = await AiNativeVectorIndexBuilder().backfillIndexedBooks(
      db,
      shouldCancel: () => progress.isNotEmpty,
      onProgress: progress.add,
    );

    expect(result.cancelled, true);
    expect(result.totalCandidates, 2);
    expect(result.booksProcessed, 1);
    expect(progress.single.done, 1);
    expect(progress.single.total, 2);
  });

  test('inspectIndexedBooks reports old indexes missing native vectors',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1);
    await _insertBook(db, 2);
    await _insertBook(db, 3, status: 'failed');
    await _insertChunk(
      db,
      bookId: 1,
      href: 'missing-native.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    final readyChunkId = await _insertChunk(
      db,
      bookId: 2,
      href: 'ready-native.xhtml',
      vector: const [0, 1],
      writeBlob: true,
    );
    await _insertChunk(
      db,
      bookId: 3,
      href: 'failed-book.xhtml',
      vector: const [1, 1],
      writeBlob: true,
    );
    await db.insert('ai_vector_index_rows', {
      'chunk_id': readyChunkId,
      'book_id': 2,
      'provider_id': 'provider-a',
      'embedding_model': 'model-a',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [0, 1]),
      'created_at': 1,
      'updated_at': 1,
    });

    final status = await AiNativeVectorIndexBuilder().inspectIndexedBooks(db);

    expect(status.indexedBookCount, 2);
    expect(status.readyBookCount, 1);
    expect(status.shadowedBookCount, 1);
    expect(status.vectorRowCount, 1);
    expect(status.missingBookCount, 1);
  });

  test('native then exact backend falls back when native search is unavailable',
      () async {
    final native = _ThrowingVectorBackend();
    final exact = _StaticVectorBackend([
      {
        'chunk_id': 7,
        'chapter_href': 'exact.xhtml',
        'local_vector_score': 0.5,
      }
    ]);
    final backend = AiNativeThenExactVectorSearchBackend(
      nativeBackend: native,
      exactBackend: exact,
    );

    final hits = await backend.searchRows(
      _RecordingNativeVectorDatabase(
        vectorRows: const [],
        hydratedRows: const [],
      ),
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(native.calls, 1);
    expect(exact.calls, 1);
    expect(hits.single['chapter_href'], 'exact.xhtml');
  });

  test(
      'native then exact backend merges exact rows while shadow index is partial',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1);
    final nativeChunkId = await _insertChunk(
      db,
      bookId: 1,
      href: 'native-only.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    await _insertBook(db, 2);
    await _insertChunk(
      db,
      bookId: 2,
      href: 'exact-only.xhtml',
      vector: const [0, 1],
      writeBlob: true,
    );
    await db.insert('ai_vector_index_rows', {
      'chunk_id': nativeChunkId,
      'book_id': 1,
      'provider_id': 'provider-a',
      'embedding_model': 'model-a',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'created_at': 1,
      'updated_at': 1,
    });

    final backend = AiNativeThenExactVectorSearchBackend(
      nativeBackend: _StaticVectorBackend([
        {
          'chunk_id': nativeChunkId,
          'chapter_href': 'native-only.xhtml',
          'local_vector_score': 0.2,
        }
      ]),
      exactBackend: const AiExactVectorSearchBackend(),
    );

    final hits = await backend.searchRows(
      db,
      queryVector: const [0, 1],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 2,
    );

    expect(hits.map((r) => r['chapter_href']).toList(), [
      'exact-only.xhtml',
      'native-only.xhtml',
    ]);
  });

  test(
      'native then exact backend skips exact scan when shadow index is complete',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1, chunkCount: 1);
    final chunkId = await _insertChunk(
      db,
      bookId: 1,
      href: 'native-ready.xhtml',
      vector: const [1, 0],
      writeBlob: true,
    );
    await db.insert('ai_vector_index_rows', {
      'chunk_id': chunkId,
      'book_id': 1,
      'provider_id': 'provider-a',
      'embedding_model': 'model-a',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'created_at': 1,
      'updated_at': 1,
    });

    final exact = _StaticVectorBackend([
      {
        'chunk_id': 99,
        'chapter_href': 'should-not-scan.xhtml',
        'local_vector_score': 1.0,
      }
    ]);
    final backend = AiNativeThenExactVectorSearchBackend(
      nativeBackend: _StaticVectorBackend([
        {
          'chunk_id': chunkId,
          'chapter_href': 'native-ready.xhtml',
          'local_vector_score': 0.8,
        }
      ]),
      exactBackend: exact,
    );

    final hits = await backend.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(exact.calls, 0);
    expect(hits.single['chapter_href'], 'native-ready.xhtml');
  });
}

class _RecordingNativeVectorDatabase implements Database {
  _RecordingNativeVectorDatabase({
    required this.vectorRows,
    required this.hydratedRows,
  });

  final List<Map<String, Object?>> vectorRows;
  final List<Map<String, Object?>> hydratedRows;
  final sqlLog = <String>[];
  final argsLog = <List<Object?>?>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    sqlLog.add(sql);
    argsLog.add(arguments);
    if (sql.contains('pragma_function_list')) {
      return const [
        {'name': 'vector_full_scan'}
      ];
    }
    if (sql.contains('vector_full_scan')) return vectorRows;
    return hydratedRows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingVectorBackend implements AiVectorSearchBackend {
  int calls = 0;

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
    calls += 1;
    throw StateError('native vector extension unavailable');
  }
}

class _StaticVectorBackend implements AiVectorSearchBackend {
  _StaticVectorBackend(this.rows);

  final List<Map<String, Object?>> rows;
  int calls = 0;

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
    calls += 1;
    return rows;
  }
}

Future<void> _insertBook(
  dynamic db,
  int bookId, {
  String status = 'succeeded',
  int chunkCount = 2,
}) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': 'provider-a',
    'embedding_model': 'model-a',
    'chunk_count': chunkCount,
    'created_at': 0,
    'updated_at': 0,
    'index_status': status,
    'indexed_at': 0,
    'failed_reason': null,
    'retry_count': 0,
    'index_version': 12,
  });
}

Future<int> _insertChunk(
  dynamic db, {
  required int bookId,
  required String href,
  required List<double> vector,
  required bool writeBlob,
}) {
  return db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': href,
    'chunk_index': 0,
    'start_char': 0,
    'end_char': 10,
    'text': href,
    'raw_text': href,
    'embedding_json': '[${vector.join(',')}]',
    'embedding_blob': writeBlob ? AiVectorCodec.encodeFloat32(vector) : null,
    'embedding_dim': vector.length,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}

Future<int> _insertInvalidChunk(
  dynamic db, {
  required int bookId,
  required String href,
}) {
  return db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': href,
    'chunk_index': 0,
    'start_char': 0,
    'end_char': 10,
    'text': href,
    'raw_text': href,
    'embedding_json': 'not-json',
    'embedding_blob': null,
    'embedding_dim': 2,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}
