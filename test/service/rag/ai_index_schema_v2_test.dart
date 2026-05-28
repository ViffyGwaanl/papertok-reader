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

    final jobCols = await handle.rawQuery('PRAGMA table_info(ai_index_jobs)');
    final jobNames = jobCols.map((c) => c['name']?.toString()).toList();

    expect(jobNames, contains('phase'));
    expect(jobNames, contains('done_chapters'));
    expect(jobNames, contains('total_chapters'));
    expect(jobNames, contains('done_chunks'));
    expect(jobNames, contains('total_chunks'));
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
  });
}
