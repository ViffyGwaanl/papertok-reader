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

  test('sqlite vector backend skips unbounded native scan for book scope',
      () async {
    final db = _RecordingNativeVectorDatabase(
      vectorRows: const [
        {'chunk_id': 42, 'local_vector_score': 0.99},
      ],
      hydratedRows: const [
        {
          'chunk_id': 42,
          'book_id': 34,
          'chapter_href': 'native.xhtml',
          'local_vector_score': 0.99,
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
      maxScanRows: 3,
      bookId: 34,
    );

    expect(hits, isEmpty);
    expect(
      db.sqlLog.any((sql) => sql.contains('vector_full_scan')),
      false,
    );
  });

  test('vec1 table name is stable per provider model and dimension', () {
    final a = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
    );
    final b = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
    );
    final c = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 1024,
    );

    expect(a, b);
    expect(a, startsWith('ai_vec1_index_'));
    expect(a, isNot(contains('/')));
    expect(a, isNot(c));
  });

  test('vec1 book table name is stable per provider model dimension and book',
      () {
    final global = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
    );
    final a = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
      bookId: 34,
    );
    final b = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
      bookId: 34,
    );
    final c = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'provider/a',
      embeddingModel: 'Qwen/Qwen3-Embedding-8B',
      embeddingDim: 4096,
      bookId: 35,
    );

    expect(a, b);
    expect(a, startsWith('ai_vec1_book_index_'));
    expect(a, isNot(contains('/')));
    expect(a, isNot(global));
    expect(a, isNot(c));
  });

  test('vec1 backend uses per-model virtual table and hydrates winners',
      () async {
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    final db = _RecordingVec1Database(
      tableName: tableName,
      vectorRows: [
        {'chunk_id': 42, 'local_vector_score': 0.97},
      ],
      hydratedRows: [
        {
          'chunk_id': 42,
          'book_id': 1,
          'chapter_href': 'vec1.xhtml',
          'chapter_title': 'Vec1',
          'chunk_index': 0,
          'start_char': 0,
          'end_char': 9,
          'text': 'vec1 text',
          'raw_text': 'vec1 text',
          'context_text': 'vec1 text',
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

    final hits = await const AiVec1VectorSearchBackend().searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(hits, hasLength(1));
    expect(hits.single['chapter_href'], 'vec1.xhtml');
    expect(hits.single['local_vector_score'], 0.97);
    expect(db.sqlLog.any((sql) => sql.contains('vec1_info()')), true);
    expect(db.sqlLog.any((sql) => sql.contains('$tableName(')), true);
    expect(db.sqlLog.last, contains('ai_chunks'));
  });

  test('vec1 backend uses per-book table for book-scoped recall', () async {
    final globalTable = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    final bookTable = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
      bookId: 34,
    );
    final db = _RecordingVec1Database(
      tableNames: {bookTable},
      vectorRowsByTable: {
        bookTable: [
          {'chunk_id': 42, 'local_vector_score': 0.98},
        ],
      },
      hydratedRows: [
        {
          'chunk_id': 42,
          'book_id': 34,
          'chapter_href': 'book-scope.xhtml',
          'chapter_title': 'Book Scope',
          'chunk_index': 0,
          'start_char': 0,
          'end_char': 9,
          'text': 'book text',
          'raw_text': 'book text',
          'context_text': 'book text',
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

    final hits = await const AiVec1VectorSearchBackend().searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
      bookId: 34,
    );

    expect(hits, hasLength(1));
    expect(hits.single['chapter_href'], 'book-scope.xhtml');
    expect(db.sqlLog.any((sql) => sql.contains('$bookTable(')), true);
    expect(db.sqlLog.any((sql) => sql.contains('$globalTable(')), false);
  });

  test('vec1 builder rebuilds per-model tables from native shadow rows',
      () async {
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    final db = _RecordingVec1BuildDatabase(tableName: tableName);

    final result =
        await const AiVec1VectorIndexBuilder().rebuildFromNativeShadowRows(db);

    expect(result.available, true);
    expect(result.tablesBuilt, 1);
    expect(result.rowsWritten, 2);
    expect(
      db.executeLog.first,
      contains('CREATE VIRTUAL TABLE IF NOT EXISTS'),
    );
    expect(db.executeLog.first, contains(tableName));
    expect(db.executeLog.first, contains('USING vec1'));
    expect(db.executeLog, hasLength(2));
    expect(db.deleteLog, contains(tableName));
    expect(db.insertLog.where((e) => e.table == tableName), hasLength(2));
    expect(
      db.insertLog.where((e) => e.table == db.bookTableName),
      hasLength(2),
    );
    expect(
      db.insertLog
          .where((e) => e.table == 'ai_vector_index_meta')
          .single
          .values['backend'],
      AiVec1VectorIndexBuilder.backendId,
    );
  });

  test('vec1 builder can cancel while writing a large table', () async {
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    final db = _RecordingVec1BuildDatabase(tableName: tableName);

    final result =
        await const AiVec1VectorIndexBuilder().rebuildFromNativeShadowRows(
      db,
      shouldCancel: () => db.insertLog.any((e) => e.table == tableName),
    );

    expect(result.cancelled, true);
    expect(result.tablesBuilt, 0);
    expect(result.rowsWritten, 1);
    expect(db.insertLog.where((e) => e.table == tableName), hasLength(1));
    expect(
      db.insertLog.where((e) => e.table == 'ai_vector_index_meta'),
      isEmpty,
    );
  });

  test('vec1 status reports partial ANN tables per provider model group',
      () async {
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    final db = _RecordingVec1StatusDatabase(
      tableName: tableName,
      nativeRowCount: 2,
      annRowCount: 1,
    );

    final status =
        await const AiVec1VectorIndexBuilder().inspectBuildStatus(db);

    expect(status.available, true);
    expect(status.totalGroups, 1);
    expect(status.readyGroups, 0);
    expect(status.missingGroupCount, 1);
    expect(status.nativeRowCount, 2);
    expect(status.annRowCount, 1);
    expect(status.canBuild, true);
  });

  test('ann then native backend uses book-scoped ANN before fallback',
      () async {
    final ann = _StaticVectorBackend([
      {
        'chunk_id': 7,
        'book_id': 34,
        'chapter_href': 'book-scoped-ann.xhtml',
        'local_vector_score': 1.0,
      }
    ]);
    final native = _StaticVectorBackend([
      {
        'chunk_id': 7,
        'book_id': 34,
        'chapter_href': 'book-scoped-native.xhtml',
        'local_vector_score': 0.8,
      }
    ]);
    final backend = AiAnnThenNativeThenExactVectorSearchBackend(
      annBackend: ann,
      nativeThenExactBackend: native,
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
      bookId: 34,
    );

    expect(ann.calls, 1);
    expect(ann.bookIds, [34]);
    expect(native.calls, 0);
    expect(native.bookIds, isEmpty);
    expect(hits.single['chapter_href'], 'book-scoped-ann.xhtml');
  });

  test('ann then native backend prefers complete vec1 rows before fallback',
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
      href: 'ann-ready.xhtml',
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
    final tableName = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      embeddingDim: 2,
    );
    await db.execute('CREATE TABLE $tableName (chunk_id INTEGER PRIMARY KEY)');
    await db.insert(tableName, {'chunk_id': chunkId});

    final fallback = _StaticVectorBackend([
      {
        'chunk_id': 99,
        'chapter_href': 'should-not-fallback.xhtml',
        'local_vector_score': 1.0,
      }
    ]);
    final backend = AiAnnThenNativeThenExactVectorSearchBackend(
      annBackend: _StaticVectorBackend([
        {
          'chunk_id': chunkId,
          'chapter_href': 'ann-ready.xhtml',
          'local_vector_score': 0.8,
        }
      ]),
      nativeThenExactBackend: fallback,
    );

    final hits = await backend.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(fallback.calls, 0);
    expect(hits.single['chapter_href'], 'ann-ready.xhtml');
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

class _RecordingVec1Database implements Database {
  _RecordingVec1Database({
    String? tableName,
    List<Map<String, Object?>>? vectorRows,
    Set<String>? tableNames,
    Map<String, List<Map<String, Object?>>>? vectorRowsByTable,
    required this.hydratedRows,
  })  : tableNames = tableNames ?? {tableName!},
        vectorRowsByTable = vectorRowsByTable ??
            {
              tableName!: vectorRows ?? const <Map<String, Object?>>[],
            };

  final Set<String> tableNames;
  final Map<String, List<Map<String, Object?>>> vectorRowsByTable;
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
    if (sql.contains('vec1_info()')) {
      return const [
        {'info': 'vec1 test'}
      ];
    }
    if (sql.contains('sqlite_master')) {
      final name = arguments?.isNotEmpty == true ? arguments!.first : null;
      return tableNames.contains(name)
          ? [
              {'name': name}
            ]
          : const [];
    }
    if (sql.contains('LEFT JOIN')) return const [];
    for (final entry in vectorRowsByTable.entries) {
      if (sql.contains('${entry.key}(')) return entry.value;
    }
    return hydratedRows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingVec1BuildDatabase implements Database {
  _RecordingVec1BuildDatabase({required this.tableName})
      : bookTableName = AiVec1VectorIndexBuilder.tableNameForBook(
          providerId: 'provider-a',
          embeddingModel: 'model-a',
          embeddingDim: 2,
          bookId: 1,
        );

  final String tableName;
  final String bookTableName;
  final executeLog = <String>[];
  final deleteLog = <String>[];
  final insertLog = <_RecordedInsert>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executeLog.add(sql);
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    deleteLog.add(table);
    return 0;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    insertLog.add(_RecordedInsert(table, values));
    return insertLog.length;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql.contains('vec1_info()')) {
      return const [
        {'info': 'vec1 test'}
      ];
    }
    if (sql.contains('GROUP BY provider_id')) {
      return const [
        {
          'provider_id': 'provider-a',
          'embedding_model': 'model-a',
          'embedding_dim': 2,
          'row_count': 2,
        }
      ];
    }
    if (sql.contains('FROM ai_vector_index_rows')) {
      return [
        {
          'chunk_id': 41,
          'book_id': 1,
          'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
        },
        {
          'chunk_id': 42,
          'book_id': 1,
          'embedding_blob': AiVectorCodec.encodeFloat32(const [0, 1]),
        },
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingVec1StatusDatabase implements Database {
  _RecordingVec1StatusDatabase({
    required this.tableName,
    required this.nativeRowCount,
    required this.annRowCount,
  });

  final String tableName;
  final int nativeRowCount;
  final int annRowCount;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql.contains('vec1_info()')) {
      return const [
        {'info': 'vec1 test'}
      ];
    }
    if (sql.contains('GROUP BY provider_id')) {
      return [
        {
          'provider_id': 'provider-a',
          'embedding_model': 'model-a',
          'embedding_dim': 2,
          'row_count': nativeRowCount,
        }
      ];
    }
    if (sql.contains('sqlite_master')) {
      return [
        {'name': tableName}
      ];
    }
    if (sql.contains('COUNT(*)') && sql.contains(tableName)) {
      return [
        {'row_count': annRowCount}
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordedInsert {
  const _RecordedInsert(this.table, this.values);

  final String table;
  final Map<String, Object?> values;
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
    int? bookId,
  }) async {
    calls += 1;
    throw StateError('native vector extension unavailable');
  }
}

class _StaticVectorBackend implements AiVectorSearchBackend {
  _StaticVectorBackend(this.rows);

  final List<Map<String, Object?>> rows;
  int calls = 0;
  final List<int?> bookIds = [];

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
    calls += 1;
    bookIds.add(bookId);
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
