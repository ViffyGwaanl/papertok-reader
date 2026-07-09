import 'dart:async';
import 'dart:io';
import 'package:papertok_reader/utils/get_path/get_cache_dir.dart';
import 'package:papertok_reader/utils/platform_utils.dart';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/dao/book.dart';
import 'package:papertok_reader/service/book.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/utils/get_path/databases_path.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Current app database version
const int currentDbVersion = 8;

const createBookSQL = '''
CREATE TABLE tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  cover_path TEXT,
  file_path TEXT,
  last_read_position TEXT,
  reading_percentage REAL,
  author TEXT,
  is_deleted INTEGER,
  description TEXT,
  create_time TEXT,
  update_time TEXT,
  rating REAL,
  group_id INTEGER,
  file_md5 TEXT,
  bookmark_data BLOB,
  source_kind TEXT DEFAULT 'imported'
)
''';

const createThemeSQL = '''
CREATE TABLE tb_themes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  background_color TEXT,
  text_color TEXT,
  background_image_path TEXT
)
''';

const createStyleSQL = '''
CREATE TABLE tb_styles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  font_size REAL,
  font_family TEXT,
  line_height REAL,
  letter_spacing REAL,
  word_spacing REAL,
  paragraph_spacing REAL,
  side_margin REAL,
  top_margin REAL,
  bottom_margin REAL
)
''';

const primaryTheme1 = '''
INSERT INTO tb_themes (background_color, text_color, background_image_path) VALUES ('fffbfbf3', 'ff343434', '')
''';
const primaryTheme2 = '''
INSERT INTO tb_themes (background_color, text_color, background_image_path) VALUES ('ff040404', 'fffeffeb', '')
''';

const createNoteSQL = '''
CREATE TABLE tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  content TEXT,
  cfi TEXT,
  chapter TEXT,
  type TEXT,
  color TEXT,
  create_time TEXT,
  update_time TEXT,
  reader_note TEXT
)
''';

const createReadingTimeSQL = '''
CREATE TABLE tb_reading_time (
  id INTEGER PRIMARY KEY,
  book_id INTEGER,
  date TEXT,
  reading_time INTEGER
)
''';

const createGroupSQL = '''
CREATE TABLE tb_groups (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  parent_id INTEGER,
  is_deleted INTEGER DEFAULT 0,
  create_time TEXT,
  update_time TEXT,
  FOREIGN KEY (parent_id) REFERENCES tb_groups(id)
)
''';

const insertRootGroupSQL = '''
INSERT OR IGNORE INTO tb_groups (id, name, parent_id, create_time, update_time)
VALUES (0, 'Root', NULL, datetime('now'), datetime('now'))
''';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  static bool updatedDB = false;

  factory DBHelper() {
    return _instance;
  }

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    int dbVersion = currentDbVersion;
    switch (AnxPlatform.type) {
      case AnxPlatformEnum.macos:
      case AnxPlatformEnum.android:
      case AnxPlatformEnum.ohos:
        final databasePath = await getAnxDataBasesPath();
        final path = join(databasePath, 'app_database.db');
        final db = await openDatabase(
          path,
          version: dbVersion,
          onCreate: (db, version) async {
            await onCreateDatabase(db, version);
          },
          onUpgrade: onUpgradeDatabase,
        );
        await ensureCriticalSchema(db);
        return db;
      case AnxPlatformEnum.ios:
      case AnxPlatformEnum.windows:
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;

        final databasePath = await getAnxDataBasesPath();
        AnxLog.info('Database: database path: $databasePath');
        final path = join(databasePath, 'app_database.db');

        final db = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: dbVersion,
            onCreate: (db, version) async {
              await onCreateDatabase(db, version);
            },
            onUpgrade: onUpgradeDatabase,
          ),
        );
        await ensureCriticalSchema(db);
        return db;
    }
  }

  /// Creates the complete current-version schema for a fresh install.
  ///
  /// Fresh installs must NOT run the upgrade chain: createBookSQL already
  /// bakes in columns (rating, group_id, ...) that the chain re-adds via
  /// ALTER TABLE, which throws "duplicate column" and aborts everything
  /// after it (tb_groups, reader_note) — leaving the install permanently
  /// unable to save highlights, notes, or groups.
  Future<void> onCreateDatabase(Database db, int version) async {
    AnxLog.info('Database: create fresh database version $version');
    await db.execute(createBookSQL);
    await db.execute(createNoteSQL);
    await db.execute(createThemeSQL);
    await db.execute(createStyleSQL);
    await db.execute(createReadingTimeSQL);
    await db.execute(createGroupSQL);
    await db.execute(primaryTheme1);
    await db.execute(primaryTheme2);
    await db.execute(insertRootGroupSQL);
  }

  /// Repairs databases created by builds where the fresh-install migration
  /// chain aborted mid-way (missing tb_notes / tb_groups / reader_note).
  /// Idempotent; a no-op on healthy databases. Best-effort: a repair
  /// failure must never block app startup.
  Future<void> ensureCriticalSchema(Database db) async {
    try {
      final notes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tb_notes'");
      if (notes.isEmpty) {
        AnxLog.warning('Database: repairing missing tb_notes table');
        await db.execute(createNoteSQL);
      } else {
        final noteColumns = await db.rawQuery('PRAGMA table_info(tb_notes)');
        final hasReaderNote =
            noteColumns.any((column) => column['name'] == 'reader_note');
        if (!hasReaderNote) {
          AnxLog.warning(
              'Database: repairing missing tb_notes.reader_note column');
          await db.execute('ALTER TABLE tb_notes ADD COLUMN reader_note TEXT');
        }
      }
      final groups = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tb_groups'");
      if (groups.isEmpty) {
        AnxLog.warning('Database: repairing missing tb_groups table');
        await db.execute(createGroupSQL);
      }
      // Always re-assert the root row: INSERT OR IGNORE is a no-op when it
      // exists and covers a kill between table creation and seeding.
      await db.execute(insertRootGroupSQL);
    } catch (e, st) {
      AnxLog.severe('Database: ensureCriticalSchema failed', e, st);
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Checkpoint WAL to merge data into main database file
  /// Returns true if checkpoint was successful or not needed
  static Future<bool> checkpointWal() async {
    try {
      final db = await DBHelper().database;
      // Use rawQuery instead of execute for PRAGMA wal_checkpoint
      // because it returns a result row which can cause issues with execute()
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      AnxLog.info('Database: WAL checkpoint completed');
      return true;
    } catch (e) {
      AnxLog.warning('Database: WAL checkpoint failed: $e');
      return false;
    }
  }

  /// Get the path to the WAL file for a database
  static String getWalPath(String dbPath) => '$dbPath-wal';

  /// Get the path to the SHM file for a database
  static String getShmPath(String dbPath) => '$dbPath-shm';

  /// Check if WAL files exist for a database and have content
  static bool hasWalFiles(String dbPath) {
    final walFile = File(getWalPath(dbPath));
    return walFile.existsSync() && walFile.lengthSync() > 0;
  }

  /// Delete WAL auxiliary files
  static Future<void> cleanupWalFiles(String dbPath) async {
    try {
      final walFile = File(getWalPath(dbPath));
      final shmFile = File(getShmPath(dbPath));
      if (walFile.existsSync()) await walFile.delete();
      if (shmFile.existsSync()) await shmFile.delete();
      AnxLog.info('Database: WAL files cleaned up');
    } catch (e) {
      AnxLog.warning('Database: Failed to cleanup WAL files: $e');
    }
  }

  /// Create a snapshot of the database for upload using VACUUM INTO
  /// This avoids closing the database or locking it for long periods
  static Future<String> prepareUploadSnapshot() async {
    try {
      final db = await DBHelper().database;
      final cacheDir = await getAnxCacheDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final snapshotPath = join(cacheDir.path, 'snapshot_aaaa_$timestamp.db');

      // Ensure any existing file is removed
      final snapshotFile = File(snapshotPath);
      if (snapshotFile.existsSync()) {
        await snapshotFile.delete();
      }

      // VACUUM INTO creates a transactionally consistent copy
      // It works even if the DB is in WAL mode and open
      try {
        // Use string interpolation instead of binding for VACUUM INTO
        // as some SQLite wrappers/versions don't support bindings in VACUUM statements
        final escapedPath = snapshotPath.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$escapedPath'");
      } catch (e) {
        AnxLog.warning('Database: VACUUM INTO failed ($e)');

        // Fallback strategy for platforms with older SQLite versions
        // (SQLite 3.27.0+ required for VACUUM INTO support)
        AnxLog.info('Database: Using fallback strategy (Checkpoint+Copy)');

        // 1. Force Checkpoint to ensure all WAL data is written to main DB file
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

        // 2. Copy file manually
        final databasePath = await getAnxDataBasesPath();
        final dbPath = join(databasePath, 'app_database.db');
        await File(dbPath).copy(snapshotPath);
      }

      AnxLog.info('Database: Created snapshot at $snapshotPath');

      // Ensure the snapshot has a clean header (Legacy mode)
      // This guarantees the uploaded file is compatible with all platforms
      await fixDatabaseHeader(snapshotPath);

      return snapshotPath;
    } catch (e) {
      AnxLog.severe('Database: Failed to create snapshot: $e');
      rethrow;
    }
  }

  /// Directly patch the database file header to switch from WAL mode to Legacy mode
  /// WAL mode sets the file format byte (offset 18) and version byte (offset 19) to 2
  /// We need to reset them to 1 (Legacy) to allow opening without -wal file
  static Future<void> fixDatabaseHeader(String dbPath) async {
    try {
      final file = File(dbPath);
      if (!file.existsSync()) return;

      // 1. Check header first to avoid expensive read/write if not needed
      bool needsPatch = false;
      final raf = await file.open(mode: FileMode.read);
      try {
        if (await raf.length() > 20) {
          await raf.setPosition(18);
          final writeVersion = await raf.readByte();
          final readVersion = await raf.readByte();

          if (writeVersion == 2 || readVersion == 2) {
            needsPatch = true;
            AnxLog.info(
                'Database: Detected WAL mode in header (v$writeVersion/v$readVersion), patching to Legacy mode');
          }
        }
      } finally {
        await raf.close();
      }

      // 2. Patch if needed logic (Read-Modify-Write)
      if (needsPatch) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 20) {
          bytes[18] = 1; // Write version: 1 (Legacy)
          bytes[19] = 1; // Read version: 1 (Legacy)

          await file.writeAsBytes(bytes, flush: true);
          AnxLog.info('Database: patched header 18, 19 to 1 successfully');
        }
      }
    } catch (e) {
      AnxLog.warning('Database: Failed to patch database header: $e');
    }
  }

  /// Get the latest modification time including WAL file
  /// This ensures we detect changes even if they're only in the WAL
  static DateTime getLatestModTime(String dbPath) {
    final dbFile = File(dbPath);
    final walFile = File(getWalPath(dbPath));

    DateTime dbTime = dbFile.existsSync()
        ? dbFile.lastModifiedSync()
        : DateTime.fromMillisecondsSinceEpoch(0);

    if (walFile.existsSync()) {
      DateTime walTime = walFile.lastModifiedSync();
      if (walTime.isAfter(dbTime)) {
        return walTime;
      }
    }

    return dbTime;
  }

  Future<void> onUpgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    AnxLog.info('Database: upgrade database from $oldVersion to $newVersion');
    if (oldVersion == 0) {
      // Fresh installs go through onCreateDatabase; running the ALTER chain
      // against the baked-in createBookSQL columns throws duplicate-column.
      // Defensive-only: production initDB always supplies onCreate, so
      // sqflite never routes version 0 here unless that wiring changes.
      await onCreateDatabase(db, newVersion);
      return;
    }
    switch (oldVersion) {
      case 1:
        // add a column (rating) to tb_books
        await db.execute('ALTER TABLE tb_books ADD COLUMN rating REAL');
        // Remove absolute Android app_flutter prefixes from imported databases.
        //
        // Why: when users import/export databases across forks/distributions, some
        // older DB snapshots may have absolute paths like:
        //   /data/user/0/<package>/app_flutter/...
        // We normalize them into relative paths so the current install can
        // resolve files under its own sandbox.
        const androidAppFlutterPrefixes = [
          '/data/user/0/com.anxcye.anx_reader/app_flutter/',
          '/data/user/0/com.gwaanl.paperreader/app_flutter/',
          '/data/user/0/ai.papertok.paperreader/app_flutter/',
        ];
        for (final prefix in androidAppFlutterPrefixes) {
          await db.execute(
              "UPDATE tb_books SET file_path = REPLACE(file_path, '$prefix', '')");
          await db.execute(
              "UPDATE tb_books SET cover_path = REPLACE(cover_path, '$prefix', '')");
        }
        continue case2;
      case2:
      case 2:
        // replave ' ' with '_' in db and cut file name to 25
        await db.execute(
            "UPDATE tb_books SET file_path = REPLACE(file_path, ' ', '_')");
        await db.execute(
            "UPDATE tb_books SET cover_path = REPLACE(cover_path, ' ', '_')");
        await db.execute(
            "UPDATE tb_books SET file_path = SUBSTR(file_path, 0, 25)");
        await db.execute(
            "UPDATE tb_books SET cover_path = SUBSTR(cover_path, 0, 25)");
        await db
            .execute("UPDATE tb_books SET file_path = file_path || '.epub'");
        await db
            .execute("UPDATE tb_books SET cover_path = cover_path || '.png'");

        final basePath = getBasePath('');
        final fileDir = Directory('$basePath/file');
        final coverDir = Directory('$basePath/cover');
        fileDir.listSync().forEach((element) {
          if (element is File) {
            final path = element.path;
            String pathAfterReplace = path.replaceAll(' ', '_');
            int endIndex =
                (pathAfterReplace.length < 72) ? pathAfterReplace.length : 72;
            final newPath = '${pathAfterReplace.substring(0, endIndex)}.epub';
            element.rename(newPath);
          }
        });
        coverDir.listSync().forEach((element) {
          if (element is File) {
            final path = element.path;
            String pathAfterReplace = path.replaceAll(' ', '_');
            int endIndex =
                (pathAfterReplace.length < 72) ? pathAfterReplace.length : 72;
            final newPath = '${pathAfterReplace.substring(0, endIndex)}.png';
            element.rename(newPath);
          }
        });
        continue case3;
      case3:
      case 3:
        // remove former book style
        Prefs().removeBookStyle();
        bookDao.selectBooks().then((books) {
          for (var book in books) {
            if (!File(book.coverFullPath).existsSync()) {
              resetBookCover(book);
            }
          }
        });
        continue case4;
      case4:
      case 4:
        // add a column (group_id) to tb_books, and set all group_id to 0 default
        await db.execute("ALTER TABLE tb_books ADD COLUMN group_id INTEGER");
        await db.execute("UPDATE tb_books SET group_id = 0");
        continue case5;
      case5:
      case 5:
        // add a column (reader_note) to tb_notes, null default
        await db.execute("ALTER TABLE tb_notes ADD COLUMN reader_note TEXT");
        continue case6;
      case6:
      case 6:
        // create groups table and migrate existing data
        await db.execute(createGroupSQL);
        // add a column (file_md5) to tb_books
        await db.execute("ALTER TABLE tb_books ADD COLUMN file_md5 TEXT");

        // Insert root group
        await db.execute(
            "INSERT INTO tb_groups (id, name, parent_id, create_time, update_time) VALUES (0, 'Root', NULL, datetime('now'), datetime('now'))");

        // Get all unique group_ids from books
        final List<Map<String, dynamic>> uniqueGroups = await db.rawQuery('''
          SELECT DISTINCT group_id 
          FROM tb_books 
          WHERE group_id IS NOT NULL AND group_id != 0
        ''');

        // Create groups for existing group_ids
        for (var i = 0; i < uniqueGroups.length; i++) {
          final groupId = uniqueGroups[i]['group_id'];
          await db.execute('''
            INSERT INTO tb_groups (id, name, parent_id, create_time, update_time)
            VALUES (?, '...', 0, datetime('now'), datetime('now'))
          ''', [groupId]);
        }
        continue case7;
      case7:
      case 7:
        // add columns to support iOS in-place reading via security-scoped bookmarks
        await db.execute("ALTER TABLE tb_books ADD COLUMN bookmark_data BLOB");
        await db.execute(
            "ALTER TABLE tb_books ADD COLUMN source_kind TEXT DEFAULT 'imported'");
        await db.execute(
            "UPDATE tb_books SET source_kind = 'imported' WHERE source_kind IS NULL");
    }

    if (oldVersion != 0 && Prefs().webdavStatus) {
      updatedDB = true;
    }
  }
}
