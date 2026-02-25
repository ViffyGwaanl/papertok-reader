import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
