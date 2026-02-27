import 'dart:async';
import 'dart:io';

import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local FTS/BM25 index for Markdown memory files.
///
/// This is a derived cache and can be safely deleted/rebuilt.
class MemoryIndexDatabase {
  MemoryIndexDatabase({String? path, DatabaseFactory? factory})
      : _path = path,
        _factory = factory;

  static const String fileName = 'memory_index.db';
  static const int schemaVersion = 1;

  final String? _path;
  final DatabaseFactory? _factory;

  Database? _db;

  Future<String> _resolvePath() async {
    if (_path != null && _path!.trim().isNotEmpty) {
      return _path!;
    }

    final dir = Directory(await getAnxDataBasesPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, fileName);
  }

  Future<Database> get database async {
    if (_db != null) return _db!;

    final path = await _resolvePath();
    final factory = _factory ?? databaseFactory;

    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, _) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldV, newV) async {
          // Forward-only migrations. Currently only v1.
          if (oldV < 1) {
            await _createSchema(db);
          }
        },
      ),
    );

    _db = db;
    return db;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS memory_docs (
  doc_id TEXT PRIMARY KEY,
  file_name TEXT NOT NULL,
  is_long_term INTEGER NOT NULL,
  date TEXT,
  mtime INTEGER NOT NULL,
  size INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS memory_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  start_line INTEGER,
  end_line INTEGER,
  text TEXT NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_chunks_doc ON memory_chunks(doc_id)',
    );

    // Optional: FTS5 for chunks.
    try {
      await db.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS memory_chunks_fts USING fts5(
  text,
  doc_id UNINDEXED,
  content='memory_chunks',
  content_rowid='id'
)
''');

      await db.execute('''
CREATE TRIGGER IF NOT EXISTS memory_chunks_fts_ai
AFTER INSERT ON memory_chunks
BEGIN
  INSERT INTO memory_chunks_fts(rowid, text, doc_id)
  VALUES (new.id, new.text, new.doc_id);
END;
''');

      await db.execute('''
CREATE TRIGGER IF NOT EXISTS memory_chunks_fts_ad
AFTER DELETE ON memory_chunks
BEGIN
  INSERT INTO memory_chunks_fts(memory_chunks_fts, rowid, text, doc_id)
  VALUES('delete', old.id, old.text, old.doc_id);
END;
''');

      await db.execute('''
CREATE TRIGGER IF NOT EXISTS memory_chunks_fts_au
AFTER UPDATE ON memory_chunks
BEGIN
  INSERT INTO memory_chunks_fts(memory_chunks_fts, rowid, text, doc_id)
  VALUES('delete', old.id, old.text, old.doc_id);
  INSERT INTO memory_chunks_fts(rowid, text, doc_id)
  VALUES (new.id, new.text, new.doc_id);
END;
''');
    } catch (_) {
      // Best-effort: platform might not support FTS5.
    }
  }
}
