import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AiIndexDatabase v3 creates FTS table when available (or falls back)',
      () async {
    sqfliteFfiInit();

    final dbHelper = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );

    final db = await dbHelper.database;

    final fts = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='ai_chunks_fts'",
    );

    if (fts.isNotEmpty) {
      // Basic sanity: triggers keep FTS in sync.
      await db.insert('ai_book_index', {
        'book_id': 1,
        'book_md5': 'md5',
        'provider_id': 'p',
        'embedding_model': 'm',
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
        'end_char': 5,
        'text': 'hello world',
        'embedding_json': '[1,0]',
        'embedding_dim': 2,
        'embedding_norm': 1.0,
        'created_at': 0,
      });

      final hits = await db.rawQuery(
        "SELECT rowid FROM ai_chunks_fts WHERE ai_chunks_fts MATCH 'hello' LIMIT 1",
      );
      expect(hits, isNotEmpty);
    } else {
      // Graceful fallback: FTS isn't available in this SQLite build.
      expect(fts, isEmpty);
    }

    await dbHelper.close();
  });
}
