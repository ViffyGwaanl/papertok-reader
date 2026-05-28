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
