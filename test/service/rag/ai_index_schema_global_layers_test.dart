import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_schema.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('AiIndexDatabase creates RAPTOR and GraphRAG layer tables', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    final tables = await sqlite.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual')",
    );
    final names = tables.map((r) => r['name']).whereType<String>().toSet();

    expect(await sqlite.getVersion(), kAiIndexDbVersion);
    expect(names, contains('ai_raptor_nodes'));
    expect(names, contains('ai_raptor_node_chunks'));
    expect(names, contains('ai_graph_nodes'));
    expect(names, contains('ai_graph_edges'));
    expect(names, contains('ai_graph_node_chunks'));
    expect(names, contains('ai_graph_communities'));
    expect(names, contains('ai_graph_community_nodes'));

    final graphNodeIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_graph_nodes')");
    final graphNodeIndexNames =
        graphNodeIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(graphNodeIndexNames, contains('idx_ai_graph_nodes_book_type_name'));

    final raptorIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_raptor_nodes')");
    final raptorIndexNames =
        raptorIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(raptorIndexNames, contains('idx_ai_raptor_nodes_book_level'));
  });

  test('AiIndexDatabase creates native vector shadow index tables', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    final tables = await sqlite.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual')",
    );
    final names = tables.map((r) => r['name']).whereType<String>().toSet();

    expect(await sqlite.getVersion(), kAiIndexDbVersion);
    expect(names, contains('ai_vector_index_rows'));
    expect(names, contains('ai_vector_index_meta'));

    final rowCols =
        await sqlite.rawQuery('PRAGMA table_info(ai_vector_index_rows)');
    final rowNames = rowCols.map((r) => r['name']).whereType<String>().toSet();
    expect(rowNames, contains('chunk_id'));
    expect(rowNames, contains('book_id'));
    expect(rowNames, contains('provider_id'));
    expect(rowNames, contains('embedding_model'));
    expect(rowNames, contains('embedding_dim'));
    expect(rowNames, contains('embedding_blob'));

    final rowIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_vector_index_rows')");
    final rowIndexNames =
        rowIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(rowIndexNames, contains('idx_ai_vector_rows_model_dim'));
    expect(rowIndexNames, contains('idx_ai_vector_rows_book'));
  });

  test('clearBook removes derived global and vector index layers', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    await sqlite.insert('ai_book_index', {
      'book_id': 7,
      'book_md5': 'md5-7',
      'provider_id': 'p',
      'embedding_model': 'm',
      'chunk_count': 1,
      'created_at': 0,
      'updated_at': 0,
      'index_status': 'succeeded',
    });
    final chunkId = await sqlite.insert('ai_chunks', {
      'book_id': 7,
      'chapter_href': 'Text/ch.xhtml',
      'chapter_title': 'Chapter',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 10,
      'text': 'vector graph evidence',
      'embedding_json': '[1,0]',
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });
    final raptorId = await sqlite.insert('ai_raptor_nodes', {
      'book_id': 7,
      'level': 1,
      'summary': 'raptor',
    });
    await sqlite.insert('ai_raptor_node_chunks', {
      'node_id': raptorId,
      'chunk_id': chunkId,
    });
    final graphNodeId = await sqlite.insert('ai_graph_nodes', {
      'book_id': 7,
      'node_type': 'term',
      'name': 'Graph',
    });
    await sqlite.insert('ai_graph_node_chunks', {
      'node_id': graphNodeId,
      'chunk_id': chunkId,
    });
    await sqlite.insert('ai_vector_index_rows', {
      'chunk_id': chunkId,
      'book_id': 7,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
    });
    await sqlite.insert('ai_vector_index_meta', {
      'id': 'native-sql-shadow::p::m::2',
      'backend': 'native-sql-shadow',
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'index_status': 'ready',
      'row_count': 1,
    });
    final annTable = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'p',
      embeddingModel: 'm',
      embeddingDim: 2,
    );
    final bookAnnTable = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'p',
      embeddingModel: 'm',
      embeddingDim: 2,
      bookId: 7,
    );
    await sqlite.execute('''
CREATE TABLE $annTable (
  rowid INTEGER PRIMARY KEY,
  embedding BLOB,
  chunk_id INTEGER,
  book_id INTEGER
)
''');
    await sqlite.execute('''
CREATE TABLE $bookAnnTable (
  rowid INTEGER PRIMARY KEY,
  embedding BLOB,
  chunk_id INTEGER,
  book_id INTEGER
)
''');
    await sqlite.insert(annTable, {
      'rowid': chunkId,
      'embedding': AiVectorCodec.encodeFloat32(const [1, 0]),
      'chunk_id': chunkId,
      'book_id': 7,
    });
    await sqlite.insert(bookAnnTable, {
      'rowid': chunkId,
      'embedding': AiVectorCodec.encodeFloat32(const [1, 0]),
      'chunk_id': chunkId,
      'book_id': 7,
    });
    await sqlite.insert('ai_vector_index_meta', {
      'id': 'vec1-ann::p::m::2',
      'backend': AiVec1VectorIndexBuilder.backendId,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'index_status': 'ready',
      'row_count': 1,
    });

    await db.clearBook(7);

    Future<int> count(String table) async {
      final rows = await sqlite.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    expect(await count('ai_book_index'), 0);
    expect(await count('ai_chunks'), 0);
    expect(await count('ai_raptor_nodes'), 0);
    expect(await count('ai_graph_nodes'), 0);
    expect(await count('ai_vector_index_rows'), 0);
    expect(await count(annTable), 0);
    expect(await count(bookAnnTable), 0);
    final metaRows = await sqlite.query('ai_vector_index_meta');
    expect(metaRows, isEmpty);
  });

  test('clearBook removes orphaned per-book ANN sidecar rows', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    await sqlite.insert('ai_book_index', {
      'book_id': 7,
      'book_md5': 'md5-7',
      'provider_id': 'p',
      'embedding_model': 'm',
      'chunk_count': 1,
      'created_at': 0,
      'updated_at': 0,
      'index_status': 'succeeded',
    });
    final chunkId = await sqlite.insert('ai_chunks', {
      'book_id': 7,
      'chapter_href': 'Text/ch.xhtml',
      'chapter_title': 'Chapter',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 10,
      'text': 'vector sidecar evidence',
      'embedding_json': '[1,0]',
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });
    await sqlite.insert('ai_vector_index_rows', {
      'chunk_id': chunkId,
      'book_id': 7,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
    });
    final bookAnnTable = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'p',
      embeddingModel: 'm',
      embeddingDim: 2,
      bookId: 7,
    );
    await sqlite.execute('''
CREATE TABLE $bookAnnTable (
  rowid INTEGER PRIMARY KEY,
  embedding BLOB,
  chunk_id INTEGER,
  book_id INTEGER
)
''');
    await sqlite.insert(bookAnnTable, {
      'rowid': chunkId,
      'embedding': AiVectorCodec.encodeFloat32(const [1, 0]),
      'chunk_id': chunkId,
      'book_id': 7,
    });
    await sqlite.insert('ai_vector_index_meta', {
      'id': 'vec1-ann::p::m::2',
      'backend': AiVec1VectorIndexBuilder.backendId,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'index_status': 'ready',
      'row_count': 1,
    });

    await db.clearBook(7);

    final sidecarRows =
        await sqlite.rawQuery('SELECT COUNT(*) AS c FROM $bookAnnTable');
    expect((sidecarRows.first['c'] as num).toInt(), 0);
    final metaRows = await sqlite.query('ai_vector_index_meta');
    expect(metaRows, isEmpty);
  });

  test('clearBook preserves other books sharing the same vector group',
      () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    final annTable = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'p',
      embeddingModel: 'm',
      embeddingDim: 2,
    );
    final bookAnnTables = {
      for (final bookId in [7, 8])
        bookId: AiVec1VectorIndexBuilder.tableNameForBook(
          providerId: 'p',
          embeddingModel: 'm',
          embeddingDim: 2,
          bookId: bookId,
        ),
    };
    await sqlite.execute('''
CREATE TABLE $annTable (
  rowid INTEGER PRIMARY KEY,
  embedding BLOB,
  chunk_id INTEGER,
  book_id INTEGER
)
''');
    for (final table in bookAnnTables.values) {
      await sqlite.execute('''
CREATE TABLE $table (
  rowid INTEGER PRIMARY KEY,
  embedding BLOB,
  chunk_id INTEGER,
  book_id INTEGER
)
''');
    }

    for (final bookId in [7, 8]) {
      await sqlite.insert('ai_book_index', {
        'book_id': bookId,
        'book_md5': 'md5-$bookId',
        'provider_id': 'p',
        'embedding_model': 'm',
        'chunk_count': 1,
        'created_at': 0,
        'updated_at': 0,
        'index_status': 'succeeded',
      });
      final chunkId = await sqlite.insert('ai_chunks', {
        'book_id': bookId,
        'chapter_href': 'Text/$bookId.xhtml',
        'chapter_title': 'Chapter $bookId',
        'chunk_index': 0,
        'start_char': 0,
        'end_char': 10,
        'text': 'vector evidence $bookId',
        'embedding_json': '[1,0]',
        'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
        'embedding_dim': 2,
        'embedding_norm': 1.0,
        'created_at': 0,
      });
      await sqlite.insert('ai_vector_index_rows', {
        'chunk_id': chunkId,
        'book_id': bookId,
        'provider_id': 'p',
        'embedding_model': 'm',
        'embedding_dim': 2,
        'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      });
      await sqlite.insert(annTable, {
        'rowid': chunkId,
        'embedding': AiVectorCodec.encodeFloat32(const [1, 0]),
        'chunk_id': chunkId,
        'book_id': bookId,
      });
      await sqlite.insert(bookAnnTables[bookId]!, {
        'rowid': chunkId,
        'embedding': AiVectorCodec.encodeFloat32(const [1, 0]),
        'chunk_id': chunkId,
        'book_id': bookId,
      });
    }
    await sqlite.insert('ai_vector_index_meta', {
      'id': 'legacy-native-meta',
      'backend': AiNativeVectorIndexBuilder.backendId,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'index_status': 'ready',
      'row_count': 2,
    });
    await sqlite.insert('ai_vector_index_meta', {
      'id': 'legacy-ann-meta',
      'backend': AiVec1VectorIndexBuilder.backendId,
      'provider_id': 'p',
      'embedding_model': 'm',
      'embedding_dim': 2,
      'index_status': 'ready',
      'row_count': 2,
    });

    await db.clearBook(7);

    Future<int> count(String table) async {
      final rows = await sqlite.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return (rows.first['c'] as num).toInt();
    }

    expect(await count('ai_book_index'), 1);
    expect(await count('ai_chunks'), 1);
    expect(await count('ai_vector_index_rows'), 1);
    expect(await count(annTable), 1);
    expect(await count(bookAnnTables[7]!), 0);
    expect(await count(bookAnnTables[8]!), 1);
    final metaRows = await sqlite.query(
      'ai_vector_index_meta',
      orderBy: 'backend ASC',
    );
    expect(metaRows, hasLength(2));
    expect(
      metaRows.map((row) => row['row_count']),
      everyElement(1),
    );
  });
}
