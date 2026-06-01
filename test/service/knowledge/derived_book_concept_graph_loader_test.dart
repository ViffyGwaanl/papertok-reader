import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/derived_book_concept_graph_loader.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('maps full-book GraphRAG rows into read-only grounded graph', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 7);
    final memoryChunkId = await _insertChunk(
      db,
      bookId: 7,
      href: 'Text/memory.xhtml',
      title: 'Memory',
      chunkIndex: 0,
      text: 'Working memory controls attention while reading.',
    );
    final attentionChunkId = await _insertChunk(
      db,
      bookId: 7,
      href: 'Text/attention.xhtml',
      title: 'Attention',
      chunkIndex: 1,
      text: 'Attention control filters irrelevant details.',
    );

    final memoryNodeId = await db.insert('ai_graph_nodes', {
      'book_id': 7,
      'node_type': 'term',
      'name': 'Working memory',
      'canonical_name': 'working memory',
      'summary': 'Temporary storage for reading context.',
      'confidence': 0.9,
      'created_at': 123,
      'updated_at': 124,
    });
    final attentionNodeId = await db.insert('ai_graph_nodes', {
      'book_id': 7,
      'node_type': 'term',
      'name': 'Attention control',
      'canonical_name': 'attention control',
      'summary': 'Filtering and focus during reading.',
      'confidence': 0.8,
      'created_at': 125,
      'updated_at': 126,
    });
    await db.insert('ai_graph_node_chunks', {
      'node_id': memoryNodeId,
      'chunk_id': memoryChunkId,
      'role': 'mention',
    });
    await db.insert('ai_graph_node_chunks', {
      'node_id': attentionNodeId,
      'chunk_id': attentionChunkId,
      'role': 'mention',
    });
    await db.insert('ai_graph_edges', {
      'book_id': 7,
      'src_node_id': memoryNodeId,
      'dst_node_id': attentionNodeId,
      'relation': 'supports',
      'weight': 0.75,
      'evidence_count': 2,
      'created_at': 127,
      'updated_at': 128,
    });

    final snapshot = await AiGlobalDerivedBookConceptGraphLoader(database: aiDb)
        .loadBook(bookId: 7);

    expect(snapshot.bookId, 7);
    expect(snapshot.nodes.map((node) => node.label), [
      'Working memory',
      'Attention control',
    ]);
    expect(snapshot.nodes.every((node) => node.sourceRefs.isNotEmpty), true);
    expect(
      snapshot.nodes
          .every((node) => node.ownership == AiOutputOwnership.derivedCache),
      true,
    );
    expect(snapshot.nodes.first.sourceRefs.single.bookId, 7);
    expect(snapshot.nodes.first.sourceRefs.single.chunkId, memoryChunkId);
    expect(snapshot.nodes.first.sourceRefs.single.href, 'Text/memory.xhtml');
    expect(snapshot.nodes.first.sourceRefs.single.sourceKind,
        SourceRefKind.libraryRag);
    expect(snapshot.nodes.first.sourceRefs.single.createdAt, 123);
    expect(snapshot.nodes.first.sourceRefs.single.sourceHash, isNotEmpty);
    expect(snapshot.nodes.first.sourceRefs.single.jumpLink,
        contains('paperreader://reader/open'));

    expect(snapshot.edges, hasLength(1));
    expect(snapshot.edges.single.type, ConceptEdgeType.supports);
    expect(snapshot.edges.single.ownership, AiOutputOwnership.derivedCache);
    expect(snapshot.edges.single.evidenceRefs, hasLength(2));
  });

  test('hides graph nodes that do not have chunk evidence', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 8);
    await db.insert('ai_graph_nodes', {
      'book_id': 8,
      'node_type': 'term',
      'name': 'Ungrounded node',
      'canonical_name': 'ungrounded node',
      'summary': 'No chunk link.',
      'confidence': 0.7,
      'created_at': 123,
      'updated_at': 124,
    });

    final snapshot = await AiGlobalDerivedBookConceptGraphLoader(database: aiDb)
        .loadBook(bookId: 8);

    expect(snapshot.isEmpty, true);
  });

  test('lists indexed books that have global graph layers', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    await _insertBook(db, 7);
    await _insertBook(db, 8);
    await db.insert('ai_raptor_nodes', {
      'book_id': 7,
      'level': 1,
      'title': 'Book summary',
      'summary': 'Global summary.',
      'child_count': 2,
      'created_at': 10,
      'updated_at': 11,
    });
    final source = await db.insert('ai_graph_nodes', {
      'book_id': 7,
      'node_type': 'term',
      'name': 'Working memory',
      'canonical_name': 'working memory',
      'summary': 'Memory node.',
      'confidence': 0.9,
      'created_at': 12,
      'updated_at': 13,
    });
    final target = await db.insert('ai_graph_nodes', {
      'book_id': 7,
      'node_type': 'term',
      'name': 'Attention',
      'canonical_name': 'attention',
      'summary': 'Attention node.',
      'confidence': 0.8,
      'created_at': 14,
      'updated_at': 15,
    });
    await db.insert('ai_graph_edges', {
      'book_id': 7,
      'src_node_id': source,
      'dst_node_id': target,
      'relation': 'related_to',
      'weight': 0.7,
      'evidence_count': 1,
      'created_at': 16,
      'updated_at': 17,
    });

    final books = await AiGlobalDerivedBookConceptGraphCatalog(
      database: aiDb,
      bookTitleLookup: (_) async => const {
        7: 'Working Memory Handbook',
        8: 'Unbuilt Book',
      },
    ).listBooks();

    expect(books, hasLength(1));
    expect(books.single.bookId, 7);
    expect(books.single.title, 'Working Memory Handbook');
    expect(books.single.chunkCount, 2);
    expect(books.single.raptorNodes, 1);
    expect(books.single.graphNodes, 2);
    expect(books.single.graphEdges, 1);
    expect(books.single.hasGlobalLayer, true);
    expect(books.single.hasGraphPreview, true);
  });
}

Future<void> _insertBook(dynamic db, int bookId) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': 'p',
    'embedding_model': 'test-model',
    'chunk_count': 2,
    'created_at': 0,
    'updated_at': 0,
    'index_status': 'succeeded',
    'indexed_at': 0,
    'failed_reason': null,
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
  required String text,
}) {
  return db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': href,
    'chapter_title': title,
    'chapter_order': 0,
    'chunk_index': chunkIndex,
    'start_char': chunkIndex * 100,
    'end_char': (chunkIndex + 1) * 100,
    'text': text,
    'raw_text': text,
    'embedding_json': '[1,0]',
    'embedding_dim': 2,
    'embedding_norm': 1.0,
    'created_at': 0,
  });
}
