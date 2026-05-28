import 'package:papertok_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

// NOTE: This DB is intended to be rebuildable. Keep migrations forward-only.
const int kAiIndexDbVersion = 8;

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
        case 5:
          await _v5(db);
        case 6:
          await _v6(db);
        case 7:
          await _v7(db);
        case 8:
          await _v8(db);
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

  static Future<void> _v5(Database db) async {
    // Persist the detailed library-indexing heartbeat so the settings UI can
    // show whether the active book is fetching text or generating embeddings.
    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {
        // Ignore duplicate column errors.
      }
    }

    await addColumn('ALTER TABLE ai_index_jobs ADD COLUMN phase TEXT');
    await addColumn(
      'ALTER TABLE ai_index_jobs ADD COLUMN done_chapters INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_index_jobs ADD COLUMN total_chapters INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_index_jobs ADD COLUMN done_chunks INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_index_jobs ADD COLUMN total_chunks INTEGER DEFAULT 0',
    );
  }

  static Future<void> _v6(Database db) async {
    // Preserve richer retrieval structure for contextual chunks and
    // parent/neighbor expansion while keeping old indexes readable.
    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {
        // Ignore duplicate column errors.
      }
    }

    await addColumn('ALTER TABLE ai_chunks ADD COLUMN raw_text TEXT');
    await addColumn('ALTER TABLE ai_chunks ADD COLUMN context_text TEXT');
    await addColumn(
      'ALTER TABLE ai_chunks ADD COLUMN embedding_input_hash TEXT',
    );
    await addColumn('ALTER TABLE ai_chunks ADD COLUMN context_model TEXT');
    await addColumn(
      'ALTER TABLE ai_chunks ADD COLUMN context_version INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_chunks ADD COLUMN context_created_at INTEGER',
    );
    await addColumn(
      'ALTER TABLE ai_chunks ADD COLUMN chapter_order INTEGER DEFAULT 0',
    );
    await addColumn(
      'ALTER TABLE ai_chunks ADD COLUMN toc_level INTEGER DEFAULT 0',
    );
    await addColumn('ALTER TABLE ai_chunks ADD COLUMN toc_path TEXT');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chunks_book_href_index '
      'ON ai_chunks(book_id, chapter_href, chunk_index)',
    );
  }

  static Future<void> _v7(Database db) async {
    // Global retrieval layers. These tables are intentionally optional at query
    // time: if no background summarization/extraction has populated them yet,
    // the ordinary chunk RAG path remains fully functional.
    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_raptor_nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  level INTEGER NOT NULL DEFAULT 0,
  parent_id INTEGER,
  cluster_id TEXT,
  title TEXT,
  summary TEXT NOT NULL,
  embedding_json TEXT,
  embedding_dim INTEGER,
  embedding_norm REAL,
  child_count INTEGER DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES ai_raptor_nodes(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_raptor_node_chunks (
  node_id INTEGER NOT NULL,
  chunk_id INTEGER NOT NULL,
  PRIMARY KEY (node_id, chunk_id),
  FOREIGN KEY (node_id) REFERENCES ai_raptor_nodes(id) ON DELETE CASCADE,
  FOREIGN KEY (chunk_id) REFERENCES ai_chunks(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_graph_nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  node_type TEXT NOT NULL,
  name TEXT NOT NULL,
  canonical_name TEXT,
  summary TEXT,
  embedding_json TEXT,
  embedding_dim INTEGER,
  embedding_norm REAL,
  confidence REAL DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_graph_edges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  src_node_id INTEGER NOT NULL,
  dst_node_id INTEGER NOT NULL,
  relation TEXT NOT NULL,
  weight REAL DEFAULT 1,
  evidence_count INTEGER DEFAULT 0,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE,
  FOREIGN KEY (src_node_id) REFERENCES ai_graph_nodes(id) ON DELETE CASCADE,
  FOREIGN KEY (dst_node_id) REFERENCES ai_graph_nodes(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_graph_node_chunks (
  node_id INTEGER NOT NULL,
  chunk_id INTEGER NOT NULL,
  role TEXT,
  PRIMARY KEY (node_id, chunk_id),
  FOREIGN KEY (node_id) REFERENCES ai_graph_nodes(id) ON DELETE CASCADE,
  FOREIGN KEY (chunk_id) REFERENCES ai_chunks(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_graph_communities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  level INTEGER NOT NULL DEFAULT 0,
  title TEXT,
  summary TEXT NOT NULL,
  embedding_json TEXT,
  embedding_dim INTEGER,
  embedding_norm REAL,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY (book_id) REFERENCES ai_book_index(book_id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_graph_community_nodes (
  community_id INTEGER NOT NULL,
  node_id INTEGER NOT NULL,
  PRIMARY KEY (community_id, node_id),
  FOREIGN KEY (community_id) REFERENCES ai_graph_communities(id) ON DELETE CASCADE,
  FOREIGN KEY (node_id) REFERENCES ai_graph_nodes(id) ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_raptor_nodes_book_level '
      'ON ai_raptor_nodes(book_id, level)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_raptor_nodes_parent '
      'ON ai_raptor_nodes(parent_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_graph_nodes_book_type_name '
      'ON ai_graph_nodes(book_id, node_type, canonical_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_graph_edges_src '
      'ON ai_graph_edges(src_node_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_graph_edges_dst '
      'ON ai_graph_edges(dst_node_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_graph_communities_book_level '
      'ON ai_graph_communities(book_id, level)',
    );
  }

  static Future<void> _v8(Database db) async {
    Future<void> addColumn(String ddl) async {
      try {
        await db.execute(ddl);
      } catch (_) {
        // Ignore duplicate column errors.
      }
    }

    await addColumn('ALTER TABLE ai_chunks ADD COLUMN embedding_blob BLOB');
  }
}
