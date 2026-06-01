import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('exact vector backend ranks by cosine and filters provider/model',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1, providerId: 'provider-a', model: 'model-a');
    await _insertBook(db, 2, providerId: 'provider-b', model: 'model-b');
    await _insertChunk(
      db,
      bookId: 1,
      href: 'mid.xhtml',
      vector: const [0.8, 0.2],
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'best.xhtml',
      vector: const [1, 0],
    );
    await _insertChunk(
      db,
      bookId: 2,
      href: 'wrong-provider.xhtml',
      vector: const [1, 0],
    );

    const backend = AiExactVectorSearchBackend();
    final hits = await backend.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 2,
    );

    expect(hits.map((e) => e['chapter_href']).toList(), [
      'best.xhtml',
      'mid.xhtml',
    ]);
  });

  test('exact vector backend scans compact vectors before hydrating winners',
      () async {
    final db = _RecordingVectorDatabase(
      scanRows: [
        _vectorScanRow(
          id: 1,
          href: 'miss.xhtml',
          vector: const [0, 1],
        ),
        _vectorScanRow(
          id: 2,
          href: 'hit.xhtml',
          vector: const [1, 0],
        ),
      ],
      hydratedRows: [
        _hydratedVectorRow(
          id: 2,
          href: 'hit.xhtml',
          text: 'winner body text',
          vector: const [1, 0],
        ),
      ],
    );

    const backend = AiExactVectorSearchBackend();
    final hits = await backend.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 1,
    );

    expect(hits, hasLength(1));
    expect(hits.single['chapter_href'], 'hit.xhtml');
    expect(hits.single['text'], 'winner body text');
    expect(db.sqlLog, hasLength(2));
    final scanSql = db.sqlLog.first;
    expect(scanSql, isNot(contains('c.text')));
    expect(scanSql, isNot(contains('c.raw_text')));
    expect(scanSql, isNot(contains('c.context_text')));
    expect(scanSql, isNot(contains('c.embedding_json')));
    final hydrateSql = db.sqlLog.last;
    expect(hydrateSql, contains('c.text'));
    expect(hydrateSql, contains('c.raw_text'));
    expect(hydrateSql, contains('c.context_text'));
    expect(db.argsLog.last, contains(2));
  });

  test('SemanticSearchLibrary vector fallback uses injected backend', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await _insertBook(db, 1, providerId: 'provider-a', model: 'model-a');
    await _insertChunk(
      db,
      bookId: 1,
      href: 'backend-hit.xhtml',
      vector: const [1, 0],
      text: 'semantic-only passage',
    );
    final row = (await db.rawQuery('''
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
LIMIT 1
''')).single;

    final backend = _FakeVectorBackend([row]);
    final service = SemanticSearchLibrary(
      database: aiDb,
      vectorSearch: backend,
      embedQuery: (q, {required model, providerId}) async => const [1, 0],
    );

    final result = await service.search(
      query: 'no lexical match',
      maxResults: 1,
    );

    expect(backend.calls, 1);
    expect(result.ok, true);
    expect(result.usedVectorFallback, true);
    expect(result.evidence.single.href, 'backend-hit.xhtml');
  });
}

class _RecordingVectorDatabase implements Database {
  _RecordingVectorDatabase({
    required this.scanRows,
    required this.hydratedRows,
  });

  final List<Map<String, Object?>> scanRows;
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
    if (sqlLog.length == 1) {
      return scanRows;
    }
    return hydratedRows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVectorBackend implements AiVectorSearchBackend {
  _FakeVectorBackend(this.rows);

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
    calls++;
    return rows;
  }
}

Map<String, Object?> _vectorScanRow({
  required int id,
  required String href,
  required List<double> vector,
}) {
  return {
    'chunk_id': id,
    'book_id': 1,
    'chapter_href': href,
    'chapter_title': href,
    'chunk_index': 0,
    'start_char': 0,
    'end_char': 10,
    'embedding_input_hash': 'hash-$id',
    'context_version': 0,
    'context_created_at': 0,
    'embedding_blob': AiVectorCodec.encodeFloat32(vector),
    'embedding_norm': 1.0,
    'embedding_model': 'model-a',
    'provider_id': 'provider-a',
    'index_version': 1,
  };
}

Map<String, Object?> _hydratedVectorRow({
  required int id,
  required String href,
  required String text,
  required List<double> vector,
}) {
  return {
    ..._vectorScanRow(id: id, href: href, vector: vector),
    'text': text,
    'raw_text': text,
    'context_text': text,
    'embedding_json': '[${vector.join(',')}]',
  };
}

Future<void> _insertBook(
  dynamic db,
  int bookId, {
  required String providerId,
  required String model,
}) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': providerId,
    'embedding_model': model,
    'chunk_count': 1,
    'created_at': 0,
    'updated_at': 0,
    'index_status': 'succeeded',
    'indexed_at': 0,
    'failed_reason': null,
    'retry_count': 0,
    'index_version': 1,
  });
}

Future<void> _insertChunk(
  dynamic db, {
  required int bookId,
  required String href,
  required List<double> vector,
  String text = 'vector passage',
}) async {
  await db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': href,
    'chunk_index': 0,
    'start_char': 0,
    'end_char': 10,
    'text': text,
    'raw_text': text,
    'embedding_json': '[0,1]',
    'embedding_blob': AiVectorCodec.encodeFloat32(vector),
    'embedding_dim': vector.length,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}
