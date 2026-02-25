import 'package:anx_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

// NOTE: This DB is intended to be rebuildable. Keep migrations forward-only.
const int kAiIndexDbVersion = 4;

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

    // Run incremental migrations.
    var v = oldVersion;
    while (v < newVersion) {
      v += 1;
      switch (v) {
        case 1:
          await _v1(db);
        case 2:
          await _v2(db);
        case 3:
          await _v3(db);
        case 4:
          await _v4(db);
      }
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

  static Future<void> _v2(Database db) async {
    // Extend ai_book_index with library-level indexing metadata.
    // SQLite has limited ALTER TABLE support, so we add columns one by one.
    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {
        // Ignore duplicate column errors.
      }
    }

    await addColumn(
      "ALTER TABLE ai_book_index ADD COLUMN index_status TEXT DEFAULT 'idle'",
    );
    await addColumn(
      'ALTER TABLE ai_book_index ADD COLUMN indexed_at INTEGER',
    );
    await addColumn(
      'ALTER TABLE ai_book_index ADD COLUMN failed_reason TEXT',
    );
    await addColumn(
      'ALTER TABLE ai_book_index ADD COLUMN retry_count INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_book_index ADD COLUMN index_version INTEGER DEFAULT 1',
    );

    // Persisted library indexing queue.
    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_index_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  status TEXT NOT NULL,
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 1,
  progress REAL DEFAULT 0,
  current_chapter_href TEXT,
  current_chapter_title TEXT,
  last_error TEXT,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_index_jobs_status ON ai_index_jobs(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_index_jobs_book ON ai_index_jobs(book_id)',
    );
  }

  static Future<void> _v3(Database db) async {
    // Optional: Full-text search table for ai_chunks.
    //
    // This migration is best-effort and must not fail the entire DB open.
    // Some SQLite builds may not ship with FTS5 enabled.
    try {
      await db.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS ai_chunks_fts USING fts5(
  text,
  chapter_title,
  book_id UNINDEXED,
  chapter_href UNINDEXED,
  content='ai_chunks',
  content_rowid='id'
)
''');

      // Keep FTS in sync with ai_chunks.
      await db.execute('''
CREATE TRIGGER IF NOT EXISTS ai_chunks_fts_ai
AFTER INSERT ON ai_chunks
BEGIN
  INSERT INTO ai_chunks_fts(rowid, text, chapter_title, book_id, chapter_href)
  VALUES (new.id, new.text, new.chapter_title, new.book_id, new.chapter_href);
END;
''');

      await db.execute('''
CREATE TRIGGER IF NOT EXISTS ai_chunks_fts_ad
AFTER DELETE ON ai_chunks
BEGIN
  INSERT INTO ai_chunks_fts(ai_chunks_fts, rowid, text, chapter_title, book_id, chapter_href)
  VALUES('delete', old.id, old.text, old.chapter_title, old.book_id, old.chapter_href);
END;
''');

      await db.execute('''
CREATE TRIGGER IF NOT EXISTS ai_chunks_fts_au
AFTER UPDATE ON ai_chunks
BEGIN
  INSERT INTO ai_chunks_fts(ai_chunks_fts, rowid, text, chapter_title, book_id, chapter_href)
  VALUES('delete', old.id, old.text, old.chapter_title, old.book_id, old.chapter_href);
  INSERT INTO ai_chunks_fts(rowid, text, chapter_title, book_id, chapter_href)
  VALUES (new.id, new.text, new.chapter_title, new.book_id, new.chapter_href);
END;
''');

      // Backfill existing rows.
      await db.execute(
          "INSERT INTO ai_chunks_fts(ai_chunks_fts) VALUES('rebuild')");
    } catch (e) {
      AnxLog.warning('AiIndexDB: FTS5 not available, skip FTS migration: $e');
    }
  }

  static Future<void> _v4(Database db) async {
    // Persist indexing parameters that affect chunk layout. This is needed to
    // determine whether an existing book index is "expired" after the user
    // changes indexing settings.

    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {
        // Ignore duplicate column errors.
      }
    }

    await addColumn(
        'ALTER TABLE ai_book_index ADD COLUMN chunk_target_chars INTEGER');
    await addColumn(
        'ALTER TABLE ai_book_index ADD COLUMN chunk_max_chars INTEGER');
    await addColumn(
        'ALTER TABLE ai_book_index ADD COLUMN chunk_min_chars INTEGER');
    await addColumn(
        'ALTER TABLE ai_book_index ADD COLUMN chunk_overlap_chars INTEGER');
    await addColumn(
      'ALTER TABLE ai_book_index ADD COLUMN max_chapter_characters INTEGER',
    );
  }
}
