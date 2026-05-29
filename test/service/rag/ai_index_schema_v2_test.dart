import 'dart:io';

import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AiIndexDatabase v2 creates ai_index_jobs and new ai_book_index columns',
      () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    final handle = await db.database;

    final tables = await handle
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'")
        .then((rows) => rows.map((r) => r['name']?.toString()).toList());

    expect(tables, contains('ai_index_jobs'));

    final cols = await handle.rawQuery('PRAGMA table_info(ai_book_index)');
    final names = cols.map((c) => c['name']?.toString()).toList();

    expect(names, contains('index_status'));
    expect(names, contains('indexed_at'));
    expect(names, contains('failed_reason'));
    expect(names, contains('retry_count'));
    expect(names, contains('index_version'));
    expect(names, contains('done_chapters'));
    expect(names, contains('total_chapters'));

    final jobCols = await handle.rawQuery('PRAGMA table_info(ai_index_jobs)');
    final jobNames = jobCols.map((c) => c['name']?.toString()).toList();

    expect(jobNames, contains('phase'));
    expect(jobNames, contains('done_chapters'));
    expect(jobNames, contains('total_chapters'));
    expect(jobNames, contains('done_chunks'));
    expect(jobNames, contains('total_chunks'));
    expect(jobNames, contains('current_chapter_done_chunks'));
    expect(jobNames, contains('current_chapter_total_chunks'));
    expect(jobNames, contains('embedding_batch_index'));
    expect(jobNames, contains('embedding_batch_total'));
    expect(jobNames, contains('last_embedding_batch_size'));
    expect(jobNames, contains('last_embedding_dim'));
    expect(jobNames, contains('force_rebuild'));
  });

  test('AiIndexDatabase maps persisted chapter progress on book index info',
      () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    final db = AiIndexDatabase.forTesting(path: ':memory:', factory: factory);
    addTearDown(db.close);
    final handle = await db.database;

    await handle.insert('ai_book_index', {
      'book_id': 88,
      'chunk_count': 321,
      'done_chapters': 10,
      'total_chapters': 1000,
      'created_at': 1,
      'updated_at': 2,
    });

    final info = await db.getBookIndexInfo(88);
    expect(info, isNotNull);
    expect(info!.chunkCount, 321);
    expect(info.doneChapters, 10);
    expect(info.totalChapters, 1000);
  });

  test('AiIndexDatabase upgrades v4 ai_index_jobs with progress columns',
      () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('ai_index_v5_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final path = p.join(dir.path, 'ai_index.db');
    final oldDb = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) => AiIndexMigrations.migrate(db, 0, version),
      ),
    );
    await oldDb.close();

    final db = AiIndexDatabase.forTesting(path: path, factory: factory);
    addTearDown(db.close);
    final handle = await db.database;

    final versionRow = await handle.rawQuery('PRAGMA user_version');
    final userVersion = (versionRow.first.values.first as num).toInt();
    expect(userVersion, kAiIndexDbVersion);

    final jobCols = await handle.rawQuery('PRAGMA table_info(ai_index_jobs)');
    final jobNames = jobCols.map((c) => c['name']?.toString()).toList();

    expect(jobNames, contains('phase'));
    expect(jobNames, contains('done_chapters'));
    expect(jobNames, contains('total_chapters'));
    expect(jobNames, contains('done_chunks'));
    expect(jobNames, contains('total_chunks'));
    expect(jobNames, contains('current_chapter_done_chunks'));
    expect(jobNames, contains('current_chapter_total_chunks'));
    expect(jobNames, contains('embedding_batch_index'));
    expect(jobNames, contains('embedding_batch_total'));
    expect(jobNames, contains('last_embedding_batch_size'));
    expect(jobNames, contains('last_embedding_dim'));
    expect(jobNames, contains('force_rebuild'));

    final indexCols = await handle.rawQuery('PRAGMA table_info(ai_book_index)');
    final indexNames = indexCols.map((c) => c['name']?.toString()).toList();
    expect(indexNames, contains('done_chapters'));
    expect(indexNames, contains('total_chapters'));
  });

  test('AiIndexDatabase upgrades v5 ai_chunks with RAG structure columns',
      () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('ai_index_v6_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final path = p.join(dir.path, 'ai_index.db');
    final oldDb = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) => AiIndexMigrations.migrate(db, 0, version),
      ),
    );
    await oldDb.close();

    final db = AiIndexDatabase.forTesting(path: path, factory: factory);
    addTearDown(db.close);
    final handle = await db.database;

    final versionRow = await handle.rawQuery('PRAGMA user_version');
    final userVersion = (versionRow.first.values.first as num).toInt();
    expect(userVersion, kAiIndexDbVersion);

    final chunkCols = await handle.rawQuery('PRAGMA table_info(ai_chunks)');
    final chunkNames = chunkCols.map((c) => c['name']?.toString()).toList();

    expect(chunkNames, contains('raw_text'));
    expect(chunkNames, contains('context_text'));
    expect(chunkNames, contains('embedding_blob'));
    expect(chunkNames, contains('embedding_input_hash'));
    expect(chunkNames, contains('context_model'));
    expect(chunkNames, contains('context_version'));
    expect(chunkNames, contains('context_created_at'));
    expect(chunkNames, contains('chapter_order'));
    expect(chunkNames, contains('toc_level'));
    expect(chunkNames, contains('toc_path'));

    final indexRows = await handle.rawQuery('PRAGMA index_list(ai_chunks)');
    final indexNames = indexRows.map((c) => c['name']?.toString()).toList();
    expect(indexNames, contains('idx_ai_chunks_book_href_index'));
  });
}
