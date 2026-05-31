import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
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
}
