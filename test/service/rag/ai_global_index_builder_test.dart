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
    expect(result.evidence.single.snippet, contains('local passage'));
    expect(result.evidence.single.derivedSummary, contains('Book summary'));
  });

  test('backfills global layers for old indexed books without re-embedding',
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
      href: 'Text/old.xhtml',
      title: 'Old Index',
      chunkIndex: 0,
      rawText: 'Legacy indexed chunk about memory retrieval and attention.',
    );

    await _insertBook(db, 2);
    await _insertChunk(
      db,
      bookId: 2,
      href: 'Text/done.xhtml',
      title: 'Done Index',
      chunkIndex: 0,
      rawText: 'Already upgraded chunk about retrieval practice.',
    );

    final builder = AiGlobalIndexBuilder(database: aiDb);
    await builder.rebuildBook(bookId: 2, nowMs: 123);

    final before = await builder.listBooksMissingGlobalLayer();
    expect(before.map((s) => s.bookId), [1]);
    expect(before.single.chunkCount, 1);
    expect(before.single.raptorNodes, 0);

    final progress = <AiGlobalIndexBackfillProgress>[];
    final result = await builder.backfillMissingGlobalLayers(
      onProgress: progress.add,
      nowMs: 456,
    );

    expect(result.rebuiltBookIds, [1]);
    expect(result.failedBookIds, isEmpty);
    expect(result.totalCandidates, 1);
    expect(progress.map((p) => p.bookId), [1]);
    expect(progress.single.done, 1);
    expect(progress.single.total, 1);

    final after = await builder.listBooksMissingGlobalLayer();
    expect(after, isEmpty);

    final raptorRows = await db.query(
      'ai_raptor_nodes',
      where: 'book_id = ?',
      whereArgs: [1],
    );
    expect(raptorRows, isNotEmpty);
  });

  test('loads a single book global layer status for in-place rebuild prompts',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 7);
    await _insertChunk(
      db,
      bookId: 7,
      href: 'Text/legacy.xhtml',
      title: 'Legacy Index',
      chunkIndex: 0,
      rawText: 'Legacy indexed chunk about attention and retrieval practice.',
    );

    final builder = AiGlobalIndexBuilder(database: aiDb);

    final missing = await builder.getBookLayerStatus(7);
    expect(missing, isNotNull);
    expect(missing!.bookId, 7);
    expect(missing.chunkCount, 1);
    expect(missing.hasGlobalLayer, false);

    await builder.rebuildBook(bookId: 7, nowMs: 123);

    final upgraded = await builder.getBookLayerStatus(7);
    expect(upgraded, isNotNull);
    expect(upgraded!.hasGlobalLayer, true);
    expect(upgraded.raptorNodes, greaterThan(0));

    expect(await builder.getBookLayerStatus(999), isNull);
  });

  test('backfill cancellation reports cancelled and leaves remaining books',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    for (final bookId in [1, 2]) {
      await _insertBook(db, bookId);
      await _insertChunk(
        db,
        bookId: bookId,
        href: 'Text/$bookId.xhtml',
        title: 'Book $bookId',
        chunkIndex: 0,
        rawText: 'Legacy indexed chunk $bookId about attention retrieval.',
      );
    }

    final builder = AiGlobalIndexBuilder(database: aiDb);
    var cancel = false;

    final result = await builder.backfillMissingGlobalLayers(
      nowMs: 456,
      shouldCancel: () => cancel,
      onProgress: (_) => cancel = true,
    );

    expect(result.cancelled, true);
    expect(result.rebuiltBookIds, [1]);
    expect(result.failedBookIds, isEmpty);
    expect(result.totalCandidates, 2);

    final remaining = await builder.listBooksMissingGlobalLayer();
    expect(remaining.map((s) => s.bookId), [2]);
  });

  test('Chinese-only global layers are not repeatedly marked missing',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 3);
    await _insertChunk(
      db,
      bookId: 3,
      href: 'Text/zh.xhtml',
      title: '中文章节',
      chunkIndex: 0,
      rawText: '注意力和记忆在阅读过程中互相影响。',
    );

    final builder = AiGlobalIndexBuilder(database: aiDb);
    await builder.rebuildBook(bookId: 3, nowMs: 789);

    final graphRows = await db.query(
      'ai_graph_nodes',
      where: 'book_id = ?',
      whereArgs: [3],
    );
    expect(graphRows, isEmpty);

    final missing = await builder.listBooksMissingGlobalLayer();
    expect(missing, isEmpty);
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
