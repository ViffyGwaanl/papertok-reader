import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/models/toc_item.dart';
import 'package:papertok_reader/providers/book_toc.dart';
import 'package:papertok_reader/providers/chapter_content_bridge.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('non-rebuild reuse repairs missing chunk embeddings in place', () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    const bookId = 77;
    await _insertReusableBookIndex(db, bookId: bookId);
    final intactChunkId = await _insertChunk(
      db,
      bookId: bookId,
      chunkIndex: 0,
      rawText: 'This chunk already has a good vector.',
      embeddingJson: '[1.0,0.0]',
      embeddingDim: 2,
      embeddingBlob: AiVectorCodec.encodeFloat32(const [1.0, 0.0]),
      embeddingNorm: 1.0,
    );
    final missingChunkId = await _insertChunk(
      db,
      bookId: bookId,
      chunkIndex: 1,
      rawText: 'This chunk lost its embedding after an interrupted index run.',
      embeddingJson: '',
      embeddingDim: 0,
      embeddingNorm: 0,
    );

    var fetchChapterCount = 0;
    final embeddingRequests = <List<String>>[];
    final book = Book.mock().copyWith(
      id: bookId,
      title: 'Repairable Book',
      md5: 'md5-$bookId',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final indexerProvider = Provider<AiBookIndexer>(
      (ref) => AiBookIndexer(
        ref,
        database: aiDb,
        embedDocuments: (
          texts, {
          String model = 'test-model',
          String? providerId,
          int timeoutSeconds = 60,
        }) async {
          embeddingRequests.add(texts);
          return [
            for (final _ in texts) const [0.25, 0.75],
          ];
        },
      ),
    );
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: book,
            chapterHref: 'Text/ch1.xhtml',
            chapterTitle: 'Chapter 1',
          ),
        );
    container.read(bookTocProvider.notifier).setToc([
      TocItem(
        id: 'ch1',
        href: 'Text/ch1.xhtml',
        label: 'Chapter 1',
        subitems: const [],
        level: 0,
        startPage: 1,
        startPercentage: 0,
      ),
    ]);
    container.read(chapterContentBridgeProvider.notifier).state =
        ChapterContentHandlers(
      fetchCurrentChapter: ({int? maxCharacters}) async {
        fetchChapterCount++;
        return 'This chapter should not be fetched during in-place repair.';
      },
      fetchChapterByHref: (href, {int? maxCharacters}) async {
        fetchChapterCount++;
        return 'This chapter should not be fetched during in-place repair.';
      },
    );

    final info = await container.read(indexerProvider).buildCurrentBook(
          rebuild: false,
          embeddingProviderId: 'p',
          embeddingModel: 'test-model',
          embeddingBatchSize: 8,
          chunkTargetChars: 80,
          chunkMaxChars: 160,
          chunkMinChars: 20,
          chunkOverlapChars: 0,
          maxChapterCharacters: 1000,
        );

    expect(info.bookId, bookId);
    expect(info.indexStatus, 'succeeded');
    expect(fetchChapterCount, 0);
    expect(embeddingRequests, hasLength(1));
    expect(embeddingRequests.single, hasLength(1));
    expect(
      embeddingRequests.single.single,
      contains('interrupted index run'),
    );

    final chunks = await db.query(
      'ai_chunks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chunk_index ASC',
    );
    expect(chunks, hasLength(2));
    expect(chunks[0]['id'], intactChunkId);
    expect(chunks[0]['embedding_json'], '[1.0,0.0]');
    expect(chunks[1]['id'], missingChunkId);
    expect(chunks[1]['embedding_json'], '[0.25,0.75]');
    expect(chunks[1]['embedding_dim'], 2);
    expect(chunks[1]['embedding_blob'], isNotNull);
    expect(chunks[1]['embedding_norm'], closeTo(0.7905, 0.0001));
  });

  test('non-rebuild reuse repairs mismatched embedding dimensions in place',
      () async {
    final aiDb = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(aiDb.close);
    final db = await aiDb.database;

    const bookId = 78;
    await _insertReusableBookIndex(db, bookId: bookId);
    final currentDimChunkId = await _insertChunk(
      db,
      bookId: bookId,
      chunkIndex: 0,
      rawText: 'This chunk already matches the current embedding dimension.',
      embeddingJson: '[1.0,0.0]',
      embeddingDim: 2,
      embeddingBlob: AiVectorCodec.encodeFloat32(const [1.0, 0.0]),
      embeddingNorm: 1.0,
    );
    final staleDimChunkId = await _insertChunk(
      db,
      bookId: bookId,
      chunkIndex: 1,
      rawText: 'This chunk was embedded with an older three dimensional model.',
      embeddingJson: '[0.0,1.0,0.0]',
      embeddingDim: 3,
      embeddingBlob: AiVectorCodec.encodeFloat32(const [0.0, 1.0, 0.0]),
      embeddingNorm: 1.0,
    );
    final staleGlobalAnnTable = AiVec1VectorIndexBuilder.tableNameFor(
      providerId: 'p',
      embeddingModel: 'test-model',
      embeddingDim: 3,
    );
    final staleBookAnnTable = AiVec1VectorIndexBuilder.tableNameForBook(
      providerId: 'p',
      embeddingModel: 'test-model',
      embeddingDim: 3,
      bookId: bookId,
    );
    await _insertNativeVectorRow(
      db,
      chunkId: staleDimChunkId,
      bookId: bookId,
      embeddingDim: 3,
      vector: const [0.0, 1.0, 0.0],
    );
    await _insertAnnRows(
      db,
      globalTable: staleGlobalAnnTable,
      bookTable: staleBookAnnTable,
      chunkId: staleDimChunkId,
      bookId: bookId,
    );
    await _insertVectorMeta(
      db,
      backend: AiNativeVectorIndexBuilder.backendId,
      embeddingDim: 3,
      rowCount: 1,
    );
    await _insertVectorMeta(
      db,
      backend: AiVec1VectorIndexBuilder.backendId,
      embeddingDim: 3,
      rowCount: 1,
    );

    var fetchChapterCount = 0;
    final embeddingRequests = <List<String>>[];
    final book = Book.mock().copyWith(
      id: bookId,
      title: 'Mixed Dimension Book',
      md5: 'md5-$bookId',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final indexerProvider = Provider<AiBookIndexer>(
      (ref) => AiBookIndexer(
        ref,
        database: aiDb,
        embedDocuments: (
          texts, {
          String model = 'test-model',
          String? providerId,
          int timeoutSeconds = 60,
        }) async {
          embeddingRequests.add(texts);
          return [
            for (final _ in texts) const [0.5, 0.5],
          ];
        },
      ),
    );
    _seedCurrentBookProviders(
      container,
      book: book,
      onFetchChapter: () => fetchChapterCount++,
    );

    final info = await container.read(indexerProvider).buildCurrentBook(
          rebuild: false,
          embeddingProviderId: 'p',
          embeddingModel: 'test-model',
          embeddingBatchSize: 8,
          chunkTargetChars: 80,
          chunkMaxChars: 160,
          chunkMinChars: 20,
          chunkOverlapChars: 0,
          maxChapterCharacters: 1000,
        );

    expect(info.bookId, bookId);
    expect(info.indexStatus, 'succeeded');
    expect(fetchChapterCount, 0);
    expect(embeddingRequests, hasLength(2));
    expect(
      embeddingRequests.first.single,
      contains('current embedding dimension'),
    );
    expect(embeddingRequests.last, hasLength(1));
    expect(embeddingRequests.last.single, contains('older three dimensional'));

    final chunks = await db.query(
      'ai_chunks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chunk_index ASC',
    );
    expect(chunks, hasLength(2));
    expect(chunks[0]['id'], currentDimChunkId);
    expect(chunks[0]['embedding_json'], '[1.0,0.0]');
    expect(chunks[0]['embedding_dim'], 2);
    expect(chunks[1]['id'], staleDimChunkId);
    expect(chunks[1]['embedding_json'], '[0.5,0.5]');
    expect(chunks[1]['embedding_dim'], 2);
    expect(chunks[1]['embedding_norm'], closeTo(0.7071, 0.0001));

    expect(
      await db.query(
        'ai_vector_index_rows',
        where: 'chunk_id = ?',
        whereArgs: [staleDimChunkId],
      ),
      isEmpty,
    );
    expect(await db.query(staleGlobalAnnTable), isEmpty);
    expect(await db.query(staleBookAnnTable), isEmpty);
    expect(
      await db.query(
        'ai_vector_index_meta',
        where:
            "COALESCE(provider_id, '') = ? AND COALESCE(embedding_model, '') = ? AND embedding_dim = ?",
        whereArgs: ['p', 'test-model', 3],
      ),
      isEmpty,
    );
  });
}

Future<void> _insertReusableBookIndex(
  dynamic db, {
  required int bookId,
}) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'book_md5': 'md5-$bookId',
    'provider_id': 'p',
    'embedding_model': 'test-model',
    'chunk_count': 2,
    'created_at': 0,
    'updated_at': 0,
    'indexed_at': 0,
    'index_status': 'succeeded',
    'failed_reason': null,
    'retry_count': 0,
    'index_version': AiBookIndexer.indexAlgorithmVersion,
    'chunk_target_chars': 80,
    'chunk_max_chars': 160,
    'chunk_min_chars': 20,
    'chunk_overlap_chars': 0,
    'max_chapter_characters': 1000,
    'done_chapters': 1,
    'total_chapters': 1,
  });
}

Future<int> _insertChunk(
  dynamic db, {
  required int bookId,
  required int chunkIndex,
  required String rawText,
  required String embeddingJson,
  required int embeddingDim,
  List<int>? embeddingBlob,
  required double embeddingNorm,
}) async {
  return db.insert('ai_chunks', {
    'book_id': bookId,
    'chapter_href': 'Text/ch1.xhtml',
    'chapter_title': 'Chapter 1',
    'chunk_index': chunkIndex,
    'start_char': 0,
    'end_char': rawText.length,
    'text': rawText,
    'raw_text': rawText,
    'context_text': '',
    'embedding_input_hash': 'hash-$chunkIndex',
    'context_model': 'test-context',
    'context_version': 1,
    'context_created_at': 0,
    'chapter_order': 0,
    'toc_level': 0,
    'toc_path': 'Chapter 1',
    'embedding_json': embeddingJson,
    'embedding_blob': embeddingBlob,
    'embedding_dim': embeddingDim,
    'embedding_norm': embeddingNorm,
    'created_at': 0,
  });
}

Future<void> _insertNativeVectorRow(
  dynamic db, {
  required int chunkId,
  required int bookId,
  required int embeddingDim,
  required List<double> vector,
}) async {
  await db.insert('ai_vector_index_rows', {
    'chunk_id': chunkId,
    'book_id': bookId,
    'provider_id': 'p',
    'embedding_model': 'test-model',
    'embedding_dim': embeddingDim,
    'embedding_blob': AiVectorCodec.encodeFloat32(vector),
    'embedding_norm': 1.0,
    'created_at': 0,
    'updated_at': 0,
  });
}

Future<void> _insertAnnRows(
  dynamic db, {
  required String globalTable,
  required String bookTable,
  required int chunkId,
  required int bookId,
}) async {
  await db.execute(
    'CREATE TABLE $globalTable (chunk_id INTEGER PRIMARY KEY, book_id INTEGER)',
  );
  await db.execute(
    'CREATE TABLE $bookTable (chunk_id INTEGER PRIMARY KEY, book_id INTEGER)',
  );
  await db.insert(globalTable, {'chunk_id': chunkId, 'book_id': bookId});
  await db.insert(bookTable, {'chunk_id': chunkId, 'book_id': bookId});
}

Future<void> _insertVectorMeta(
  dynamic db, {
  required String backend,
  required int embeddingDim,
  required int rowCount,
}) async {
  await db.insert('ai_vector_index_meta', {
    'id': '$backend::p::test-model::$embeddingDim',
    'backend': backend,
    'provider_id': 'p',
    'embedding_model': 'test-model',
    'embedding_dim': embeddingDim,
    'index_status': 'ready',
    'row_count': rowCount,
    'last_error': null,
    'created_at': 0,
    'updated_at': 0,
  });
}

void _seedCurrentBookProviders(
  ProviderContainer container, {
  required Book book,
  required void Function() onFetchChapter,
}) {
  container.read(currentReadingProvider.notifier).start(
        CurrentReadingState(
          book: book,
          chapterHref: 'Text/ch1.xhtml',
          chapterTitle: 'Chapter 1',
        ),
      );
  container.read(bookTocProvider.notifier).setToc([
    TocItem(
      id: 'ch1',
      href: 'Text/ch1.xhtml',
      label: 'Chapter 1',
      subitems: const [],
      level: 0,
      startPage: 1,
      startPercentage: 0,
    ),
  ]);
  container.read(chapterContentBridgeProvider.notifier).state =
      ChapterContentHandlers(
    fetchCurrentChapter: ({int? maxCharacters}) async {
      onFetchChapter();
      return 'This chapter should not be fetched during in-place repair.';
    },
    fetchChapterByHref: (href, {int? maxCharacters}) async {
      onFetchChapter();
      return 'This chapter should not be fetched during in-place repair.';
    },
  );
}
