import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('global builder creates RAPTOR and GraphRAG layers from chunks',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 1);
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch1.xhtml',
      title: 'Alchemy',
      chunkIndex: 0,
      rawText: 'Alchemy catalyst ritual appears in the first chapter.',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch1.xhtml',
      title: 'Alchemy',
      chunkIndex: 1,
      rawText: 'The catalyst symbol returns with another ritual.',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch2.xhtml',
      title: 'Symbols',
      chunkIndex: 0,
      rawText: 'Hidden symbols explain the ritual pattern.',
      chapterOrder: 1,
    );

    final stats = await AiGlobalIndexBuilder(database: aiDb).rebuildBook(
      bookId: 1,
      nowMs: 123,
    );

    expect(stats.raptorNodes, greaterThanOrEqualTo(3));
    expect(stats.graphNodes, greaterThan(0));
    expect(stats.graphCommunities, 1);
    expect(stats.graphEdges, greaterThan(0));

    final raptorLinks = await db.query('ai_raptor_node_chunks');
    final graphLinks = await db.query('ai_graph_node_chunks');
    expect(raptorLinks, isNotEmpty);
    expect(graphLinks, isNotEmpty);
  });

  test('global builder output participates in semantic search', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 1);
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/global.xhtml',
      title: 'Global',
      chunkIndex: 0,
      rawText: 'The local passage is intentionally ordinary.',
    );

    await AiGlobalIndexBuilder(database: aiDb).rebuildBook(
      bookId: 1,
      nowMs: 123,
    );

    final result = await SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    ).search(query: 'Book summary', maxResults: 1);

    expect(result.ok, true);
    expect(result.usedVectorFallback, false);
    expect(result.evidence.single.href, 'Text/global.xhtml');
    expect(result.evidence.single.snippet, contains('Book summary'));
  });
}

Future<void> _insertBook(dynamic db, int bookId) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': 'p',
    'embedding_model': 'test-model',
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
  required String title,
  required int chunkIndex,
  required String rawText,
  int chapterOrder = 0,
}) async {
  await db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': title,
    'chunk_index': chunkIndex,
    'chapter_order': chapterOrder,
    'start_char': chunkIndex * 100,
    'end_char': (chunkIndex + 1) * 100,
    'text': rawText,
    'raw_text': rawText,
    'embedding_json': '[1,0]',
    'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
    'embedding_dim': 2,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}
