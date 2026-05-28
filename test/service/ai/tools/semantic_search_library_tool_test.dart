import 'package:papertok_reader/service/ai/tools/semantic_search_library_tool.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'semantic_search_library tool returns evidence with paperreader:// jumpLink',
      () async {
    sqfliteFfiInit();

    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );

    final db = await aiDb.database;

    await db.insert('ai_book_index', {
      'book_id': 1,
      'book_md5': 'md5',
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

    await db.insert('ai_chunks', {
      'book_id': 1,
      'chapter_href': 'Text/ch1.xhtml',
      'chapter_title': 'Chapter 1',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 20,
      'text': 'hello world: this is a test chunk',
      'embedding_json': '[1,0]',
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });

    // No dependency on the main app DB: resolve titles via stub.
    Future<Map<int, String>> resolver(Iterable<int> ids) async {
      return {for (final id in ids) id: 'Book $id'};
    }

    // Stub embedding to avoid network calls.
    Future<List<double>> embedQuery(
      String q, {
      required String model,
      String? providerId,
    }) async {
      return <double>[1, 0];
    }

    final service = SemanticSearchLibrary(
      database: aiDb,
      resolveBookTitles: resolver,
      embedQuery: embedQuery,
    );

    final tool = SemanticSearchLibraryTool(
      resolveBookTitles: resolver,
      service: service,
    );

    final out = await tool.run({
      'query': 'hello',
      'maxResults': 3,
      'onlyIndexed': true,
    });

    expect(out['ok'], true);
    expect(out['query'], 'hello');

    final evidence = (out['evidence'] as List).cast<Map<String, dynamic>>();
    expect(evidence, isNotEmpty);

    final e0 = evidence.first;
    expect(e0, containsPair('bookId', 1));
    expect(e0, containsPair('bookTitle', 'Book 1'));
    expect(e0, containsPair('href', 'Text/ch1.xhtml'));
    expect(e0, contains('anchor'));
    expect(e0, contains('snippet'));
    expect(e0, contains('score'));
    expect(e0, contains('sourceRef'));

    final jumpLink = e0['jumpLink']?.toString() ?? '';
    expect(jumpLink, startsWith('paperreader://reader/open?'));

    final uri = Uri.parse(jumpLink);
    expect(uri.scheme, 'paperreader');
    expect(uri.host, 'reader');
    expect(uri.path, '/open');
    expect(uri.queryParameters['bookId'], '1');

    final sourceRef = Map<String, dynamic>.from(e0['sourceRef'] as Map);
    expect(sourceRef, containsPair('bookId', 1));
    expect(sourceRef, containsPair('href', 'Text/ch1.xhtml'));
    expect(sourceRef['jumpLink'], jumpLink);
    expect(sourceRef, containsPair('sourceKind', 'library-rag'));
    expect(sourceRef, containsPair('derivedCacheHint', true));

    await aiDb.close();
  });

  test('semantic_search_library tool passes query variants to the service',
      () async {
    sqfliteFfiInit();

    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );

    final db = await aiDb.database;

    await db.insert('ai_book_index', {
      'book_id': 2,
      'book_md5': 'md5-2',
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

    await db.insert('ai_chunks', {
      'book_id': 2,
      'chapter_href': 'Text/car.xhtml',
      'chapter_title': 'Cars',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 20,
      'text': 'The car has a quiet electric motor.',
      'embedding_json': '[1,0]',
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });

    Future<Map<int, String>> resolver(Iterable<int> ids) async {
      return {for (final id in ids) id: 'Book $id'};
    }

    Future<List<double>> embedQuery(
      String q, {
      required String model,
      String? providerId,
    }) async {
      return <double>[1, 0];
    }

    final service = SemanticSearchLibrary(
      database: aiDb,
      resolveBookTitles: resolver,
      embedQuery: embedQuery,
    );
    final tool = SemanticSearchLibraryTool(
      resolveBookTitles: resolver,
      service: service,
    );

    final out = await tool.run({
      'query': 'automobile',
      'queryVariants': ['automobile', 'car'],
      'maxResults': 1,
      'onlyIndexed': true,
    });

    expect(out['ok'], true);
    expect(out['usedVectorFallback'], false);
    final evidence = (out['evidence'] as List).cast<Map<String, dynamic>>();
    expect(evidence.single, containsPair('bookId', 2));

    await aiDb.close();
  });

  test('semantic_search_library tool constructor can wire rerank callback',
      () async {
    sqfliteFfiInit();

    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );

    final db = await aiDb.database;

    await db.insert('ai_book_index', {
      'book_id': 3,
      'book_md5': 'md5-3',
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

    await db.insert('ai_chunks', {
      'book_id': 3,
      'chapter_href': 'Text/a.xhtml',
      'chapter_title': 'A',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 20,
      'text': 'search topic shallow overview',
      'embedding_json': '[1,0]',
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });
    await db.insert('ai_chunks', {
      'book_id': 3,
      'chapter_href': 'Text/b.xhtml',
      'chapter_title': 'B',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 20,
      'text': 'search topic deep answer',
      'embedding_json': '[0.8,0.2]',
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'created_at': 0,
    });

    Future<Map<int, String>> resolver(Iterable<int> ids) async {
      return {for (final id in ids) id: 'Book $id'};
    }

    Future<List<double>> embedQuery(
      String q, {
      required String model,
      String? providerId,
    }) async {
      return <double>[1, 0];
    }

    final tool = SemanticSearchLibraryTool(
      resolveBookTitles: resolver,
      database: aiDb,
      embedQuery: embedQuery,
      rerank: (query, candidates) async =>
          candidates.map((c) => c.anchor == 'B' ? 1.0 : 0.0).toList(),
    );

    final out = await tool.run({
      'query': 'search topic',
      'maxResults': 1,
      'onlyIndexed': true,
      'neighborWindow': 0,
    });

    final evidence = (out['evidence'] as List).cast<Map<String, dynamic>>();
    expect(evidence.single, containsPair('anchor', 'B'));

    await aiDb.close();
  });
}
