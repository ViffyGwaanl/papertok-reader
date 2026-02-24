import 'package:anx_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

const int kAiIndexDbVersion = 1;

class AiIndexMigrations {
  const AiIndexMigrations._();

  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    AnxLog.info('AiIndexDB: migrate $oldVersion -> $newVersion');

    // Always keep foreign keys enabled.
    await db.execute('PRAGMA foreign_keys = ON');

    switch (oldVersion) {
      case 0:
        await _v1(db);
    }
  }

  static Future<void> _v1(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_book_index (
  book_id INTEGER PRIMARY KEY,
  book_md5 TEXT,
  provider_id TEXT,
  embedding_model TEXT,
  chunk_count INTEGER DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter_href TEXT NOT NULL,
  chapter_title TEXT,
  chunk_index INTEGER NOT NULL,
  start_char INTEGER NOT NULL,
  end_char INTEGER NOT NULL,
  text TEXT NOT NULL,
  embedding_json TEXT NOT NULL,
  embedding_dim INTEGER,
  embedding_norm REAL,
  created_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chunks_book ON ai_chunks(book_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chunks_book_href ON ai_chunks(book_id, chapter_href)',
    );
  }
}
