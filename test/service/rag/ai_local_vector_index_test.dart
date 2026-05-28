import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_local_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('local vector index prefers binary vectors and falls back to JSON',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);

    final db = await aiDb.database;
    await db.insert('ai_book_index', {
      'book_id': 1,
      'book_md5': 'md5',
      'provider_id': 'provider',
      'embedding_model': 'model',
      'chunk_count': 2,
      'created_at': 0,
      'updated_at': 0,
      'index_status': 'succeeded',
      'indexed_at': 0,
      'failed_reason': null,
      'retry_count': 0,
      'index_version': 1,
    });
    await db.insert('ai_chunks', {
      'book_id': 1,
      'chapter_href': 'bad-json-good-blob.xhtml',
      'chapter_title': 'Good Blob',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 10,
      'text': 'good blob',
      'raw_text': 'good blob',
      'embedding_json': '[0,1]',
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });
    await db.insert('ai_chunks', {
      'book_id': 1,
      'chapter_href': 'json-only.xhtml',
      'chapter_title': 'Json Only',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 10,
      'text': 'json only',
      'raw_text': 'json only',
      'embedding_json': '[0,1]',
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });

    const index = AiLocalVectorIndex();
    final rows = await index.searchRows(
      db,
      queryVector: const [1, 0],
      providerId: 'provider',
      embeddingModel: 'model',
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.single['chapter_href'], 'bad-json-good-blob.xhtml');
  });
}
