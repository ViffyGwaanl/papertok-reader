import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/ai_index_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AiIndexDatabase creates expected tables and sets user_version',
    () async {
      sqfliteFfiInit();

      final dbHelper = AiIndexDatabase.forTesting(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );

      final Database db = await dbHelper.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final names = tables
          .map((e) => e['name']?.toString())
          .whereType<String>();
      expect(names, contains('ai_book_index'));
      expect(names, contains('ai_chunks'));

      final vRow = await db.rawQuery('PRAGMA user_version');
      final userVersion = (vRow.first.values.first as num).toInt();
      expect(userVersion, kAiIndexDbVersion);

      await dbHelper.close();
    },
  );
}
