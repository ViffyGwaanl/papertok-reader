import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test('current book vector scan is paged and fetches text only for winners',
      () async {
    final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final database = AiIndexDatabase.forTesting(
      path: '${dir.path}/ai_index.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final db = await database.database;
    await db.insert('ai_book_index', {
      'book_id': 34,
      'provider_id': 'test-provider',
      'embedding_model': 'test-model',
      'chunk_count': 5,
      'index_version': 1,
      'created_at': 1,
      'updated_at': 2,
    });

    Future<void> insertChunk({
      required int chunkIndex,
      required List<double> vector,
      required String text,
      bool writeBlob = true,
    }) async {
      await db.insert('ai_chunks', {
        'book_id': 34,
        'chapter_href': 'Text/ch$chunkIndex.xhtml',
        'chapter_title': 'Chapter $chunkIndex',
        'chunk_index': chunkIndex,
        'start_char': 0,
        'end_char': text.length,
        'text': 'context $chunkIndex',
        'raw_text': text,
        'embedding_json': '[${vector.join(',')}]',
        'embedding_blob':
            writeBlob ? AiVectorCodec.encodeFloat32(vector) : null,
        'embedding_dim': vector.length,
        'embedding_norm': 1.0,
        'embedding_input_hash': 'hash-$chunkIndex',
        'context_version': 1,
        'context_created_at': 3,
        'created_at': 3,
      });
    }

    for (var i = 0; i < 4; i++) {
      await insertChunk(
        chunkIndex: i,
        vector: const [0, 1],
        text: 'background chunk $i',
      );
    }
    await insertChunk(
      chunkIndex: 4,
      vector: const [1, 0],
      text: 'winning chunk text',
      writeBlob: false,
    );

    final scanPageSizes = <int>[];
    final scanColumns = <Set<String>>[];
    final service = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      onVectorScanPage: (rows) {
        scanPageSizes.add(rows.length);
        if (rows.isNotEmpty) {
          scanColumns.add(rows.first.keys.toSet());
        }
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence, hasLength(1));
    expect(result.evidence.single.text, 'winning chunk text');
    expect(scanPageSizes, [2, 2, 1]);
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('raw_text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('embedding_json')),
    );
  });

  test(
      'current book semantic search uses vector backend before fallback page scan',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 3);
    await _insertBook(db, bookId: 99, chunkCount: 1);
    final winnerId = await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 0,
      text: 'background text',
      rawText: 'native backend winner',
      vector: const [1, 0],
    );
    await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 1,
      text: 'needle exact text',
      rawText: 'fts candidate text',
      vector: const [0, 1],
    );
    await _insertChunk(
      db,
      bookId: 99,
      chunkIndex: 0,
      text: 'other book text',
      rawText: 'other book text',
      vector: const [1, 0],
    );

    final backend = _CurrentBookRecordingVectorBackend(
      rows: [
        {
          'chunk_id': winnerId,
          'book_id': 34,
          'chapter_href': 'Text/book34-ch0.xhtml',
          'chapter_title': 'Book 34 Chapter 0',
          'chunk_index': 0,
          'start_char': 0,
          'end_char': 15,
          'text': 'background text',
          'raw_text': 'native backend winner',
          'context_text': 'background text',
          'embedding_input_hash': 'hash-34-0',
          'context_version': 1,
          'context_created_at': 3,
          'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
          'embedding_json': '[1,0]',
          'embedding_norm': 1.0,
          'embedding_model': 'test-model',
          'provider_id': 'test-provider',
          'index_version': 1,
          'local_vector_score': 0.99,
        },
      ],
    );
    final scannedIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      vectorSearch: backend,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 1,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'semantic-only',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'native backend winner');
    expect(result.evidence.single.sourceRef?.chunkId, winnerId);
    expect(scannedIds, isEmpty);
    expect(backend.seenBookIds, [34]);
    expect(backend.seenProviderIds, ['test-provider']);
    expect(backend.seenEmbeddingModels, ['test-model']);
    expect(backend.seenMaxScanRows, [3]);
  });

  test('current book vector searches are serialized across direct callers',
      () async {
    final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final database = AiIndexDatabase.forTesting(
      path: '${dir.path}/ai_index.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final db = await database.database;
    await db.insert('ai_book_index', {
      'book_id': 34,
      'provider_id': 'test-provider',
      'embedding_model': 'test-model',
      'chunk_count': 1,
      'index_version': 1,
      'created_at': 1,
      'updated_at': 2,
    });
    await db.insert('ai_chunks', {
      'book_id': 34,
      'chapter_href': 'Text/ch.xhtml',
      'chapter_title': 'Chapter',
      'chunk_index': 0,
      'start_char': 0,
      'end_char': 11,
      'text': 'context',
      'raw_text': 'target text',
      'embedding_json': '[1,0]',
      'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
      'embedding_dim': 2,
      'embedding_norm': 1.0,
      'embedding_input_hash': 'hash',
      'context_version': 1,
      'context_created_at': 3,
      'created_at': 3,
    });

    final firstStarted = Completer<void>();
    final firstRelease = Completer<void>();
    var secondStarted = false;

    final firstService = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async {
        firstStarted.complete();
        await firstRelease.future;
        return const [1, 0];
      },
    );
    final secondService = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async {
        secondStarted = true;
        return const [1, 0];
      },
    );

    final firstFuture = firstService.search(bookId: 34, query: 'first');
    await firstStarted.future.timeout(const Duration(seconds: 2));

    final secondFuture = secondService.search(bookId: 34, query: 'second');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(secondStarted, isFalse);

    firstRelease.complete();
    final firstResult = await firstFuture;
    final secondResult = await secondFuture;

    expect(firstResult.ok, true);
    expect(secondResult.ok, true);
    expect(secondStarted, true);
  });

  test('current book vector scan coalesces rapid progress updates', () async {
    final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final database = AiIndexDatabase.forTesting(
      path: '${dir.path}/ai_index.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final db = await database.database;
    await db.insert('ai_book_index', {
      'book_id': 34,
      'provider_id': 'test-provider',
      'embedding_model': 'test-model',
      'chunk_count': 5,
      'index_version': 1,
      'created_at': 1,
      'updated_at': 2,
    });

    for (var i = 0; i < 5; i++) {
      await db.insert('ai_chunks', {
        'book_id': 34,
        'chapter_href': 'Text/ch$i.xhtml',
        'chapter_title': 'Chapter $i',
        'chunk_index': i,
        'start_char': 0,
        'end_char': 12,
        'text': 'context $i',
        'raw_text': 'target text $i',
        'embedding_json': '[1,0]',
        'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
        'embedding_dim': 2,
        'embedding_norm': 1.0,
        'embedding_input_hash': 'hash-$i',
        'context_version': 1,
        'context_created_at': 3,
        'created_at': 3,
      });
    }

    final progressEvents = <AiCurrentBookSearchProgress>[];
    final service = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 1,
      nowMs: () => 1000,
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
      onProgress: progressEvents.add,
    );

    expect(result.ok, true);
    expect(
      progressEvents.map((event) => event.scannedRows).toList(),
      [1, 5],
    );
  });

  test('current book vector scan can be cancelled after progress update',
      () async {
    final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final database = AiIndexDatabase.forTesting(
      path: '${dir.path}/ai_index.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final db = await database.database;
    await db.insert('ai_book_index', {
      'book_id': 34,
      'provider_id': 'test-provider',
      'embedding_model': 'test-model',
      'chunk_count': 4,
      'index_version': 1,
      'created_at': 1,
      'updated_at': 2,
    });

    for (var i = 0; i < 4; i++) {
      await db.insert('ai_chunks', {
        'book_id': 34,
        'chapter_href': 'Text/ch$i.xhtml',
        'chapter_title': 'Chapter $i',
        'chunk_index': i,
        'start_char': 0,
        'end_char': 12,
        'text': 'context $i',
        'raw_text': 'target text $i',
        'embedding_json': '[1,0]',
        'embedding_blob': AiVectorCodec.encodeFloat32(const [1, 0]),
        'embedding_dim': 2,
        'embedding_norm': 1.0,
        'embedding_input_hash': 'hash-$i',
        'context_version': 1,
        'context_created_at': 3,
        'created_at': 3,
      });
    }

    final token = AiCurrentBookSearchCancellationToken();
    final progressEvents = <AiCurrentBookSearchProgress>[];
    var scoreCalls = 0;
    final service = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      scoreVectorPage: ({
        required queryVector,
        required queryNorm,
        required rows,
        required jsonById,
      }) async {
        scoreCalls += 1;
        return rows
            .map(
              (row) => AiCurrentBookVectorCandidate(
                row: row,
                score: 1.0,
              ),
            )
            .toList(growable: false);
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
      cancelToken: token,
      onProgress: (progress) {
        progressEvents.add(progress);
        token.cancel();
      },
    );

    expect(result.ok, false);
    expect(result.cancelled, true);
    expect(result.evidence, isEmpty);
    expect(result.message, contains('cancelled'));
    expect(scoreCalls, 0);
    expect(progressEvents, hasLength(2));
    expect(progressEvents.first.scannedRows, 2);
    expect(progressEvents.first.progress, 0.5);
    expect(progressEvents.last.cancelled, true);
  });

  test('current book vector scan delegates scoring by page', () async {
    final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final database = AiIndexDatabase.forTesting(
      path: '${dir.path}/ai_index.db',
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final db = await database.database;
    await db.insert('ai_book_index', {
      'book_id': 34,
      'provider_id': 'test-provider',
      'embedding_model': 'test-model',
      'chunk_count': 3,
      'index_version': 1,
      'created_at': 1,
      'updated_at': 2,
    });

    for (var i = 0; i < 3; i++) {
      await db.insert('ai_chunks', {
        'book_id': 34,
        'chapter_href': 'Text/ch$i.xhtml',
        'chapter_title': 'Chapter $i',
        'chunk_index': i,
        'start_char': 0,
        'end_char': 12,
        'text': 'context $i',
        'raw_text': 'target text $i',
        'embedding_json': i == 2 ? '[1,0]' : '[0,1]',
        'embedding_blob':
            i == 2 ? null : AiVectorCodec.encodeFloat32(const [0, 1]),
        'embedding_dim': 2,
        'embedding_norm': 1.0,
        'embedding_input_hash': 'hash-$i',
        'context_version': 1,
        'context_created_at': 3,
        'created_at': 3,
      });
    }

    final pageSizes = <int>[];
    final fallbackJsonIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      scoreVectorPage: ({
        required queryVector,
        required queryNorm,
        required rows,
        required jsonById,
      }) async {
        pageSizes.add(rows.length);
        fallbackJsonIds.addAll(jsonById.keys);
        return rows.map((row) {
          final id = (row['id'] as num).toInt();
          final score = id == 3 ? 1.0 : 0.0;
          return AiCurrentBookVectorCandidate(
            row: row,
            score: score,
          );
        }).toList(growable: false);
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'target text 2');
    expect(pageSizes, [2, 1]);
    expect(fallbackJsonIds, [3]);
  });

  test('current book semantic search uses FTS candidates before vector scoring',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 6);
    await _insertBook(db, bookId: 35, chunkCount: 1);

    final candidateIds = <int>[];
    for (var i = 0; i < 4; i++) {
      candidateIds.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'needle candidate $i',
          rawText: 'candidate raw $i',
          vector: i == 3 ? const [1, 0] : const [0, 1],
        ),
      );
    }
    await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 4,
      text: 'unmatched semantic winner outside fts',
      rawText: 'outside raw',
      vector: const [1, 0],
    );
    await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 5,
      text: 'another unmatched chunk',
      rawText: 'other raw',
      vector: const [0, 1],
    );
    await _insertChunk(
      db,
      bookId: 35,
      chunkIndex: 0,
      text: 'needle from another book',
      rawText: 'other book raw',
      vector: const [1, 0],
    );

    final scannedIds = <int>[];
    final scanColumns = <Set<String>>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      ftsCandidateLimit: 4,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
        if (rows.isNotEmpty) {
          scanColumns.add(rows.first.keys.toSet());
        }
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'candidate raw 3');
    expect(scannedIds.toSet(), candidateIds.toSet());
    expect(scannedIds, hasLength(4));
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('raw_text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('embedding_json')),
    );
  });

  test(
      'current book semantic search keeps synthetic large book scans bounded by FTS candidates',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    const bookId = 34;
    const chunkCount = 640;
    const candidateLimit = 16;
    await _insertBook(db, bookId: bookId, chunkCount: chunkCount);

    final batch = db.batch();
    for (var i = 0; i < chunkCount; i++) {
      final isCandidate = i % 16 == 0;
      batch.insert(
        'ai_chunks',
        _chunkRow(
          bookId: bookId,
          chunkIndex: i,
          text: isCandidate
              ? 'needle performance candidate $i'
              : 'background performance chunk $i',
          rawText: i == 0 ? 'large-book winner raw' : 'large raw $i',
          vector: i == 0 ? const [1, 0] : const [0, 1],
        ),
      );
    }
    await batch.commit(noResult: true);

    final scannedIds = <int>[];
    final scanColumns = <Set<String>>[];
    final progressEvents = <AiCurrentBookSearchProgress>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 5,
      ftsCandidateLimit: candidateLimit,
      progressMinInterval: Duration.zero,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
        if (rows.isNotEmpty) {
          scanColumns.add(rows.first.keys.toSet());
        }
      },
    );

    final result = await service.search(
      bookId: bookId,
      query: 'needle',
      maxResults: 1,
      onProgress: progressEvents.add,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'large-book winner raw');
    expect(result.evidence.single.sourceRef, isNotNull);
    expect(result.evidence.single.sourceRef!.hasEvidence, true);
    expect(result.evidence.single.sourceRef!.chunkId, scannedIds.first);
    expect(scannedIds, hasLength(candidateLimit));
    expect(scannedIds.length, lessThan(chunkCount ~/ 10));
    expect(progressEvents.last.scannedRows, candidateLimit);
    expect(progressEvents.last.totalRows, candidateLimit);
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('raw_text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('embedding_json')),
    );
  });

  test('current book semantic search falls back when FTS has no candidates',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 3);
    final ids = <int>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'background $i',
          rawText: 'target raw $i',
          vector: i == 2 ? const [1, 0] : const [0, 1],
        ),
      );
    }

    final scannedIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      ftsCandidateLimit: 4,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'absent-token',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'target raw 2');
    expect(scannedIds, ids);
  });

  test('current book semantic search limits large fallback vector scans',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    const chunkCount = 20;
    const fallbackBudget = 5;
    await _insertBook(db, bookId: 34, chunkCount: chunkCount);
    final ids = <int>[];
    for (var i = 0; i < chunkCount; i++) {
      ids.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'background $i',
          rawText: 'target raw $i',
          vector: i == fallbackBudget - 1 ? const [1, 0] : const [0, 1],
        ),
      );
    }

    final scannedIds = <int>[];
    final scanColumns = <Set<String>>[];
    final progressEvents = <AiCurrentBookSearchProgress>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      ftsCandidateLimit: 4,
      maxFallbackVectorRows: fallbackBudget,
      progressMinInterval: Duration.zero,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
        if (rows.isNotEmpty) {
          scanColumns.add(rows.first.keys.toSet());
        }
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'absent-token',
      maxResults: 1,
      onProgress: progressEvents.add,
    );

    expect(result.ok, true);
    expect(result.message, contains('limited fallback vector scan'));
    expect(result.evidence.single.text, 'target raw ${fallbackBudget - 1}');
    expect(scannedIds, ids.take(fallbackBudget).toList(growable: false));
    expect(progressEvents.last.scannedRows, fallbackBudget);
    expect(progressEvents.last.totalRows, fallbackBudget);
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('raw_text')),
    );
    expect(
      scanColumns.expand((columns) => columns),
      isNot(contains('embedding_json')),
    );
  });

  test('current book semantic search falls back when FTS table is unavailable',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 2);
    final ids = <int>[];
    for (var i = 0; i < 2; i++) {
      ids.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'needle chunk $i',
          rawText: 'target raw $i',
          vector: i == 1 ? const [1, 0] : const [0, 1],
        ),
      );
    }
    await db.execute('DROP TABLE IF EXISTS ai_chunks_fts');

    final scannedIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 1,
      ftsCandidateLimit: 4,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'target raw 1');
    expect(scannedIds, ids);
  });

  test('current book semantic search falls back when FTS MATCH fails',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 2);
    final ids = <int>[];
    for (var i = 0; i < 2; i++) {
      ids.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'needle chunk $i',
          rawText: 'target raw $i',
          vector: i == 1 ? const [1, 0] : const [0, 1],
        ),
      );
    }
    await db.execute('DROP TABLE IF EXISTS ai_chunks_fts');
    await db.execute('''
CREATE TABLE ai_chunks_fts (
  text TEXT,
  chapter_title TEXT,
  book_id INTEGER,
  chapter_href TEXT
)
''');
    await db.insert('ai_chunks_fts', {
      'text': 'needle ordinary table row',
      'chapter_title': 'Ordinary',
      'book_id': 34,
      'chapter_href': 'Text/ordinary.xhtml',
    });

    final scannedIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 1,
      ftsCandidateLimit: 4,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'target raw 1');
    expect(scannedIds, ids);
  });

  test('current book semantic search falls back when FTS candidates are stale',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 2);
    final staleId = await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 99,
      text: 'needle stale fts row',
      rawText: 'stale raw',
      vector: const [0, 1],
    );
    await db.execute('DROP TRIGGER IF EXISTS ai_chunks_fts_ad');
    await db.delete('ai_chunks', where: 'id = ?', whereArgs: [staleId]);

    final ids = <int>[];
    for (var i = 0; i < 2; i++) {
      ids.add(
        await _insertChunk(
          db,
          bookId: 34,
          chunkIndex: i,
          text: 'background chunk $i',
          rawText: 'target raw $i',
          vector: i == 1 ? const [1, 0] : const [0, 1],
        ),
      );
    }

    final scannedIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 1,
      ftsCandidateLimit: 4,
      onVectorScanPage: (rows) {
        scannedIds.addAll(
          rows.map((row) => (row['id'] as num?)?.toInt()).whereType<int>(),
        );
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'target raw 1');
    expect(scannedIds, ids);
  });

  test(
      'current book FTS candidate scan keeps JSON fallback bounded to candidates',
      () async {
    final fixture = await _openSearchFixture();
    final db = fixture.db;

    await _insertBook(db, bookId: 34, chunkCount: 3);
    final jsonCandidateId = await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 0,
      text: 'needle json candidate',
      rawText: 'json candidate raw',
      vector: const [1, 0],
      writeBlob: false,
    );
    await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 1,
      text: 'needle blob candidate',
      rawText: 'blob candidate raw',
      vector: const [0, 1],
    );
    await _insertChunk(
      db,
      bookId: 34,
      chunkIndex: 2,
      text: 'semantic outside',
      rawText: 'outside raw',
      vector: const [1, 0],
      writeBlob: false,
    );

    final fallbackJsonIds = <int>[];
    final service = SemanticSearchCurrentBook(
      database: fixture.database,
      embedQuery: (
        text, {
        required model,
        providerId,
      }) async =>
          const [1, 0],
      vectorScanPageSize: 2,
      ftsCandidateLimit: 2,
      scoreVectorPage: ({
        required queryVector,
        required queryNorm,
        required rows,
        required jsonById,
      }) async {
        fallbackJsonIds.addAll(jsonById.keys);
        return rows.map((row) {
          final id = (row['id'] as num).toInt();
          return AiCurrentBookVectorCandidate(
            row: row,
            score: id == jsonCandidateId ? 1.0 : 0.0,
          );
        }).toList(growable: false);
      },
    );

    final result = await service.search(
      bookId: 34,
      query: 'needle',
      maxResults: 1,
    );

    expect(result.ok, true);
    expect(result.evidence.single.text, 'json candidate raw');
    expect(fallbackJsonIds, [jsonCandidateId]);
  });
}

class _SearchFixture {
  _SearchFixture({
    required this.database,
    required this.db,
  });

  final AiIndexDatabase database;
  final Database db;
}

Future<_SearchFixture> _openSearchFixture() async {
  final dir = await Directory.systemTemp.createTemp('current_book_rag_test');
  addTearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  final database = AiIndexDatabase.forTesting(
    path: '${dir.path}/ai_index.db',
    factory: databaseFactoryFfi,
  );
  addTearDown(database.close);

  final db = await database.database;
  return _SearchFixture(database: database, db: db);
}

Future<void> _insertBook(
  Database db, {
  required int bookId,
  required int chunkCount,
}) async {
  await db.insert('ai_book_index', {
    'book_id': bookId,
    'provider_id': 'test-provider',
    'embedding_model': 'test-model',
    'chunk_count': chunkCount,
    'index_version': 1,
    'created_at': 1,
    'updated_at': 2,
  });
}

Future<int> _insertChunk(
  Database db, {
  required int bookId,
  required int chunkIndex,
  required String text,
  required String rawText,
  required List<double> vector,
  bool writeBlob = true,
}) {
  return db.insert(
    'ai_chunks',
    _chunkRow(
      bookId: bookId,
      chunkIndex: chunkIndex,
      text: text,
      rawText: rawText,
      vector: vector,
      writeBlob: writeBlob,
    ),
  );
}

Map<String, Object?> _chunkRow({
  required int bookId,
  required int chunkIndex,
  required String text,
  required String rawText,
  required List<double> vector,
  bool writeBlob = true,
}) {
  return {
    'book_id': bookId,
    'chapter_href': 'Text/book$bookId-ch$chunkIndex.xhtml',
    'chapter_title': 'Book $bookId Chapter $chunkIndex',
    'chunk_index': chunkIndex,
    'start_char': 0,
    'end_char': text.length,
    'text': text,
    'raw_text': rawText,
    'embedding_json': '[${vector.join(',')}]',
    'embedding_blob': writeBlob ? AiVectorCodec.encodeFloat32(vector) : null,
    'embedding_dim': vector.length,
    'embedding_norm': 1.0,
    'embedding_input_hash': 'hash-$bookId-$chunkIndex',
    'context_version': 1,
    'context_created_at': 3,
    'created_at': 3,
  };
}

class _CurrentBookRecordingVectorBackend implements AiVectorSearchBackend {
  _CurrentBookRecordingVectorBackend({required this.rows});

  final List<Map<String, Object?>> rows;
  final List<int?> seenBookIds = [];
  final List<String> seenProviderIds = [];
  final List<String> seenEmbeddingModels = [];
  final List<int> seenMaxScanRows = [];

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
    int? bookId,
  }) async {
    seenBookIds.add(bookId);
    seenProviderIds.add(providerId);
    seenEmbeddingModels.add(embeddingModel);
    seenMaxScanRows.add(maxScanRows);
    return rows.take(limit).toList(growable: false);
  }
}
