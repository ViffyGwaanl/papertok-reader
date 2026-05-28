import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('reranker can promote a lower hybrid candidate before MMR', () async {
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
      href: 'Text/a.xhtml',
      title: 'A',
      chunkIndex: 0,
      text: 'topic common first candidate',
      embeddingJson: '[1,0]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/b.xhtml',
      title: 'B',
      chunkIndex: 0,
      text: 'topic common second candidate',
      embeddingJson: '[0,1]',
    );

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
      rerank: (query, candidates) async => [
        for (final c in candidates) c.href == 'Text/b.xhtml' ? 1.0 : 0.0,
      ],
    );

    final result = await service.search(query: 'topic', maxResults: 2);

    expect(result.ok, true);
    expect(result.evidence, isNotEmpty);
    expect(result.evidence.first.href, 'Text/b.xhtml');
  });

  test('query fusion can retrieve a synonym variant without vector fallback',
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
      href: 'Text/car.xhtml',
      title: 'Cars',
      chunkIndex: 0,
      text: 'The car has a quiet electric motor.',
      embeddingJson: '[1,0]',
    );

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(
      query: 'automobile',
      queryVariants: const ['automobile', 'car'],
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.usedVectorFallback, false);
    expect(result.evidence.single.href, 'Text/car.xhtml');
  });

  test('neighbor expansion merges adjacent chunks in the same chapter only',
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
      title: 'Chapter 1',
      chunkIndex: 0,
      text: 'previous local context',
      embeddingJson: '[0.5,0.5]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch1.xhtml',
      title: 'Chapter 1',
      chunkIndex: 1,
      text: 'needle central passage',
      embeddingJson: '[1,0]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch1.xhtml',
      title: 'Chapter 1',
      chunkIndex: 2,
      text: 'next local context',
      embeddingJson: '[0.5,0.5]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/ch2.xhtml',
      title: 'Chapter 2',
      chunkIndex: 2,
      text: 'other chapter should not leak',
      embeddingJson: '[0.5,0.5]',
    );

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(
      query: 'needle',
      maxResults: 1,
      neighborWindow: 1,
    );

    expect(result.ok, true);
    final snippet = result.evidence.single.snippet;
    expect(snippet, contains('previous local context'));
    expect(snippet, contains('needle central passage'));
    expect(snippet, contains('next local context'));
    expect(snippet, isNot(contains('other chapter should not leak')));
    expect(result.evidence.single.href, 'Text/ch1.xhtml');
  });

  test('sourceRef keeps neighbor-expanded evidence safe for export', () async {
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
      href: 'Text/long.xhtml',
      title: 'Long',
      chunkIndex: 0,
      text: List.filled(260, 'previous').join(' '),
      embeddingJson: '[0.5,0.5]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/long.xhtml',
      title: 'Long',
      chunkIndex: 1,
      text: 'needle ${List.filled(260, 'central').join(' ')}',
      embeddingJson: '[1,0]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/long.xhtml',
      title: 'Long',
      chunkIndex: 2,
      text: List.filled(260, 'next').join(' '),
      embeddingJson: '[0.5,0.5]',
    );

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(
      query: 'needle',
      maxResults: 1,
      neighborWindow: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.snippet.length, greaterThan(500));
    final json = result.evidence.single.toJson();
    final sourceRef = Map<String, dynamic>.from(json['sourceRef'] as Map);
    expect(
      (sourceRef['sourceTextSnippet'] as String).length,
      lessThanOrEqualTo(500),
    );
    expect(sourceRef['sourceKind'], 'library-rag');
    expect(sourceRef['chunkId'], isA<int>());
    expect(sourceRef['derivedCacheHint'], true);
    expect(sourceRef, isNot(contains('rawText')));
    expect(sourceRef, isNot(contains('contextText')));
    expect(sourceRef, isNot(contains('fullText')));
  });

  test('evidence snippets prefer raw text over contextual embedding text',
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
      href: 'Text/context.xhtml',
      title: 'Contextual',
      chunkIndex: 0,
      text: 'Book: Example\nPath: Hidden Context\n\nneedle raw paragraph',
      rawText: 'needle raw paragraph',
      embeddingJson: '[1,0]',
    );

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(
      query: 'needle',
      maxResults: 1,
      neighborWindow: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.snippet, 'needle raw paragraph');
  });

  test('vector fallback can find older chunks beyond the recent window',
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
      href: 'Text/old-good.xhtml',
      title: 'Old Good',
      chunkIndex: 0,
      text: 'semantic answer passage',
      embeddingJson: '[1,0]',
    );
    for (var i = 0; i < 130; i++) {
      await _insertChunk(
        db,
        bookId: 1,
        href: 'Text/recent-$i.xhtml',
        title: 'Recent $i',
        chunkIndex: 0,
        text: 'unrelated recent filler $i',
        embeddingJson: '[0,1]',
      );
    }

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(query: 'not-in-text', maxResults: 1);

    expect(result.ok, true);
    expect(result.usedVectorFallback, true);
    expect(result.evidence.single.href, 'Text/old-good.xhtml');
  });

  test('RAPTOR summaries can retrieve mapped chunk evidence', () async {
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
      href: 'Text/leaf.xhtml',
      title: 'Leaf',
      chunkIndex: 0,
      text: 'ordinary leaf passage',
      embeddingJson: '[0,1]',
    );
    final chunkId = (await db.query('ai_chunks', limit: 1)).single['id'] as int;
    final nodeId = await db.insert('ai_raptor_nodes', {
      'book_id': 1,
      'level': 1,
      'title': 'Global summary',
      'summary': 'whole book discusses deep global theme',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('ai_raptor_node_chunks', {
      'node_id': nodeId,
      'chunk_id': chunkId,
    });

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(query: 'deep global', maxResults: 1);

    expect(result.ok, true);
    expect(result.usedVectorFallback, false);
    expect(result.evidence.single.href, 'Text/leaf.xhtml');
    expect(result.evidence.single.snippet, contains('ordinary leaf passage'));
    expect(
        result.evidence.single.snippet, isNot(contains('deep global theme')));
    expect(
      result.evidence.single.derivedSummary,
      contains('deep global theme'),
    );
    expect(result.evidence.single.derivedLayer, 'raptor');
    expect(
      result.evidence.single.sourceRef!.sourceTextSnippet,
      contains('ordinary leaf passage'),
    );
  });

  test('RAPTOR summaries are fused even when leaf chunks also match', () async {
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
      href: 'Text/local.xhtml',
      title: 'Local',
      chunkIndex: 0,
      text: 'ordinary local passage',
      embeddingJson: '[0,1]',
    );
    await _insertChunk(
      db,
      bookId: 1,
      href: 'Text/global.xhtml',
      title: 'Global',
      chunkIndex: 1,
      text: 'source passage for global summary',
      embeddingJson: '[1,0]',
    );

    final globalChunkId = (await db.query(
      'ai_chunks',
      columns: ['id'],
      where: 'chapter_href = ?',
      whereArgs: ['Text/global.xhtml'],
      limit: 1,
    ))
        .single['id'] as int;
    final nodeId = await db.insert('ai_raptor_nodes', {
      'book_id': 1,
      'level': 1,
      'title': 'Atlas summary',
      'summary': 'atlas level synthesis across the book',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('ai_raptor_node_chunks', {
      'node_id': nodeId,
      'chunk_id': globalChunkId,
    });

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(
      query: 'ordinary atlas',
      maxResults: 1,
      neighborWindow: 0,
    );

    expect(result.ok, true);
    expect(result.usedVectorFallback, false);
    expect(result.evidence.single.href, 'Text/global.xhtml');
    expect(result.evidence.single.snippet,
        contains('source passage for global summary'));
    expect(
      result.evidence.single.snippet,
      isNot(contains('atlas level synthesis')),
    );
    expect(
      result.evidence.single.derivedSummary,
      contains('atlas level synthesis'),
    );
  });

  test('GraphRAG community summaries can retrieve mapped chunk evidence',
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
      href: 'Text/graph.xhtml',
      title: 'Graph',
      chunkIndex: 0,
      text: 'ordinary graph passage',
      embeddingJson: '[0,1]',
    );
    final chunkId = (await db.query('ai_chunks', limit: 1)).single['id'] as int;
    final graphNodeId = await db.insert('ai_graph_nodes', {
      'book_id': 1,
      'node_type': 'concept',
      'name': 'Hidden motif',
      'canonical_name': 'hidden motif',
      'summary': 'support node',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('ai_graph_node_chunks', {
      'node_id': graphNodeId,
      'chunk_id': chunkId,
      'role': 'support',
    });
    final communityId = await db.insert('ai_graph_communities', {
      'book_id': 1,
      'level': 0,
      'title': 'Motif community',
      'summary': 'network motif connects hidden symbols across chapters',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('ai_graph_community_nodes', {
      'community_id': communityId,
      'node_id': graphNodeId,
    });

    final service = SemanticSearchLibrary(
      database: aiDb,
      embedQuery: (q, {required model, providerId}) async => <double>[1, 0],
    );

    final result = await service.search(query: 'hidden symbols', maxResults: 1);

    expect(result.ok, true);
    expect(result.usedVectorFallback, false);
    expect(result.evidence.single.href, 'Text/graph.xhtml');
    expect(result.evidence.single.snippet, contains('ordinary graph passage'));
    expect(result.evidence.single.snippet, isNot(contains('hidden symbols')));
    expect(
      result.evidence.single.derivedSummary,
      contains('hidden symbols'),
    );
    expect(result.evidence.single.derivedLayer, 'graph');
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
  required String text,
  String? rawText,
  required String embeddingJson,
}) async {
  await db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': title,
    'chunk_index': chunkIndex,
    'start_char': chunkIndex * 100,
    'end_char': (chunkIndex + 1) * 100,
    'text': text,
    'raw_text': rawText,
    'embedding_json': embeddingJson,
    'embedding_dim': 2,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}
