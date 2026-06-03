import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test(
      'reports current book readiness across base vector global and graph layers',
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
      href: 'Text/readiness.xhtml',
      title: 'Readiness',
      chunkIndex: 0,
      rawText:
          'Attention and working memory guide reading comprehension. Attention returns as evidence.',
      embeddingJson: '[1.0,0.0]',
    );

    await const AiNativeVectorIndexBuilder().backfillBook(db, bookId: 7);
    await AiGlobalIndexBuilder(database: aiDb).rebuildBook(
      bookId: 7,
      nowMs: 123,
    );

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(7);

    expect(readiness.bookId, 7);
    expect(readiness.baseIndex.state, AiBookIndexLayerState.ready);
    expect(readiness.baseIndex.count, 1);
    expect(readiness.nativeVector.state, AiBookIndexLayerState.ready);
    expect(readiness.nativeVector.count, 1);
    expect(readiness.annVector.state, AiBookIndexLayerState.unavailable);
    expect(readiness.globalLayer.state, AiBookIndexLayerState.ready);
    expect(readiness.graphLayer.state, AiBookIndexLayerState.ready);
  });

  test('surfaces failed base index reason before derived layers', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(
      db,
      9,
      status: 'failed',
      chunkCount: 0,
      failedReason: 'embedding provider timeout',
    );

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(9);

    expect(readiness.baseIndex.state, AiBookIndexLayerState.failed);
    expect(readiness.baseIndex.reason, contains('embedding provider timeout'));
    expect(readiness.nativeVector.state, AiBookIndexLayerState.missing);
    expect(readiness.globalLayer.state, AiBookIndexLayerState.missing);
    expect(readiness.graphLayer.state, AiBookIndexLayerState.missing);
  });

  test('treats stale chunk metadata without stored chunks as missing',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 11, chunkCount: 3);

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(11);

    expect(readiness.baseIndex.state, AiBookIndexLayerState.missing);
    expect(readiness.baseIndex.count, 0);
    expect(readiness.baseIndex.reason, contains('No indexed chunks'));
    expect(readiness.nativeVector.state, AiBookIndexLayerState.missing);
    expect(readiness.canBuildGlobalLayer, false);
  });

  test('reports mixed embedding dimensions as needing embedding repair',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 13, chunkCount: 2);
    await _insertChunk(
      db,
      bookId: 13,
      href: 'Text/mixed.xhtml',
      title: 'Mixed',
      chunkIndex: 0,
      rawText: 'The first chunk uses a two dimensional embedding.',
      embeddingJson: '[1.0,0.0]',
      embeddingDim: 2,
    );
    await _insertChunk(
      db,
      bookId: 13,
      href: 'Text/mixed.xhtml',
      title: 'Mixed',
      chunkIndex: 1,
      rawText:
          'The second chunk was indexed with a stale three dimensional model.',
      embeddingJson: '[0.0,1.0,0.0]',
      embeddingDim: 3,
    );

    await const AiNativeVectorIndexBuilder().backfillBook(db, bookId: 13);

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(13);

    expect(readiness.baseIndex.state, AiBookIndexLayerState.ready);
    expect(readiness.nativeVector.state, AiBookIndexLayerState.failed);
    expect(
        readiness.nativeVector.reason, contains('Mixed embedding dimensions'));
    expect(readiness.canRepairBaseEmbeddings, true);
    expect(readiness.canUpgradeNativeVector, false);
    expect(readiness.canBuildAnnVector, false);
    expect(readiness.annVector.state, AiBookIndexLayerState.missing);
  });

  test('reports missing chunk embeddings before vector upgrades', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 14, chunkCount: 2);
    await _insertChunk(
      db,
      bookId: 14,
      href: 'Text/partial.xhtml',
      title: 'Partial',
      chunkIndex: 0,
      rawText: 'The first chunk has a reusable embedding.',
      embeddingJson: '[1.0,0.0]',
    );
    await _insertChunk(
      db,
      bookId: 14,
      href: 'Text/partial.xhtml',
      title: 'Partial',
      chunkIndex: 1,
      rawText: 'The second chunk was stored before embedding finished.',
      embeddingJson: '',
      embeddingDim: 0,
    );

    await const AiNativeVectorIndexBuilder().backfillBook(db, bookId: 14);

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(14);

    expect(readiness.baseIndex.state, AiBookIndexLayerState.ready);
    expect(readiness.baseIndex.count, 2);
    expect(readiness.nativeVector.state, AiBookIndexLayerState.failed);
    expect(readiness.nativeVector.count, 1);
    expect(readiness.nativeVector.total, 2);
    expect(readiness.nativeVector.reason, contains('1/2 chunk embeddings'));
    expect(readiness.canRepairBaseEmbeddings, true);
    expect(readiness.canUpgradeNativeVector, false);
    expect(readiness.canBuildAnnVector, false);
    expect(readiness.annVector.state, AiBookIndexLayerState.missing);
  });

  test('ignores stale native vector rows from another provider model group',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 15, chunkCount: 2);
    final firstChunkId = await _insertChunk(
      db,
      bookId: 15,
      href: 'Text/stale-vector.xhtml',
      title: 'Stale Vector',
      chunkIndex: 0,
      rawText: 'The first chunk has a current two dimensional embedding.',
      embeddingJson: '[1.0,0.0]',
      embeddingDim: 2,
    );
    final secondChunkId = await _insertChunk(
      db,
      bookId: 15,
      href: 'Text/stale-vector.xhtml',
      title: 'Stale Vector',
      chunkIndex: 1,
      rawText: 'The second chunk also has a current embedding.',
      embeddingJson: '[0.0,1.0]',
      embeddingDim: 2,
    );
    await _insertNativeVectorRow(
      db,
      chunkId: firstChunkId,
      bookId: 15,
      providerId: 'old-provider',
      embeddingModel: 'test-model',
      embeddingDim: 2,
      vector: const [1, 0],
    );
    await _insertNativeVectorRow(
      db,
      chunkId: secondChunkId,
      bookId: 15,
      providerId: 'p',
      embeddingModel: 'old-model',
      embeddingDim: 2,
      vector: const [0, 1],
    );

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(15);

    expect(readiness.baseIndex.state, AiBookIndexLayerState.ready);
    expect(readiness.nativeVector.state, AiBookIndexLayerState.missing);
    expect(readiness.nativeVector.count, 0);
    expect(readiness.nativeVector.total, 2);
    expect(readiness.nativeVector.reason, contains('0/2 compact vectors'));
    expect(readiness.canUpgradeNativeVector, true);
    expect(readiness.canBuildAnnVector, false);
    expect(readiness.annVector.state, AiBookIndexLayerState.missing);
  });

  test('reports empty graph layer when RAPTOR exists without graph nodes',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 12);
    await _insertChunk(
      db,
      bookId: 12,
      href: 'Text/zh.xhtml',
      title: '中文章节',
      chunkIndex: 0,
      rawText: '这本书有中文全局摘要层，但暂时没有可展示图谱节点。',
      embeddingJson: '[1.0,0.0]',
    );
    await _insertRaptorNode(db, bookId: 12);

    final readiness =
        await AiBookIndexReadinessInspector(database: aiDb).inspectBook(12);

    expect(readiness.globalLayer.state, AiBookIndexLayerState.ready);
    expect(readiness.globalLayer.count, 1);
    expect(readiness.graphLayer.state, AiBookIndexLayerState.empty);
    expect(readiness.graphLayer.reason, contains('no displayable graph nodes'));
  });
}

Future<void> _insertBook(
  dynamic db,
  int bookId, {
  String status = 'succeeded',
  int chunkCount = 1,
  String? failedReason,
}) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': 'p',
    'embedding_model': 'test-model',
    'chunk_count': chunkCount,
    'created_at': 0,
    'updated_at': 0,
    'index_status': status,
    'indexed_at': 0,
    'failed_reason': failedReason,
    'retry_count': 0,
    'index_version': 1,
  });
}

Future<int> _insertChunk(
  dynamic db, {
  required int bookId,
  required String href,
  required String title,
  required int chunkIndex,
  required String rawText,
  required String embeddingJson,
  int embeddingDim = 2,
}) async {
  return db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': title,
    'chapter_order': 0,
    'chunk_index': chunkIndex,
    'start_char': 0,
    'end_char': rawText.length,
    'text': rawText,
    'raw_text': rawText,
    'embedding_json': embeddingJson,
    'embedding_dim': embeddingDim,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}

Future<void> _insertNativeVectorRow(
  dynamic db, {
  required int chunkId,
  required int bookId,
  required String providerId,
  required String embeddingModel,
  required int embeddingDim,
  required List<double> vector,
}) async {
  await db.insert('ai_vector_index_rows', {
    'chunk_id': chunkId,
    'book_id': bookId,
    'provider_id': providerId,
    'embedding_model': embeddingModel,
    'embedding_dim': embeddingDim,
    'embedding_blob': AiVectorCodec.encodeFloat32(vector),
    'embedding_norm': 1.0,
    'created_at': 0,
    'updated_at': 0,
  });
}

Future<void> _insertRaptorNode(
  dynamic db, {
  required int bookId,
}) async {
  await db.insert('ai_raptor_nodes', {
    'book_id': bookId,
    'level': 2,
    'parent_id': null,
    'cluster_id': 'book:$bookId',
    'title': 'Book summary',
    'summary': 'Book summary exists without graph nodes.',
    'child_count': 1,
    'created_at': 0,
    'updated_at': 0,
  });
}
