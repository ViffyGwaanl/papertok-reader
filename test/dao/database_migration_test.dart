import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/dao/database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<bool> hasTable(Database db, String name) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [name]);
    return rows.isNotEmpty;
  }

  Future<bool> hasColumn(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((row) => row['name'] == column);
  }

  test('fresh install creates full schema including groups and reader_note',
      () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentDbVersion,
        onCreate: (db, version) async {
          await DBHelper().onCreateDatabase(db, version);
        },
        onUpgrade: DBHelper().onUpgradeDatabase,
      ),
    );

    expect(await hasTable(db, 'tb_groups'), isTrue);
    expect(await hasColumn(db, 'tb_notes', 'reader_note'), isTrue);
    for (final column in [
      'rating',
      'group_id',
      'file_md5',
      'bookmark_data',
      'source_kind',
    ]) {
      expect(await hasColumn(db, 'tb_books', column), isTrue, reason: column);
    }

    final root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));

    // The exact write paths that the aborted migration chain used to break.
    await db.insert('tb_notes', {
      'book_id': 1,
      'content': 'highlighted text',
      'cfi': 'epubcfi(/6/2!/4/2)',
      'chapter': 'chapter 1',
      'type': 'highlight',
      'color': 'ff0000',
      'create_time': '2026-07-09',
      'update_time': '2026-07-09',
      'reader_note': 'my idea',
    });
    await db.insert('tb_groups', {
      'name': 'folder',
      'parent_id': 0,
      'create_time': '2026-07-09',
      'update_time': '2026-07-09',
    });
    await db.close();
  });

  test('upgrade from v4-shape schema adds all later columns and tables',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // v4-era shape: tb_books has rating but none of the later columns;
    // tb_notes has no reader_note; tb_groups does not exist.
    await db.execute('''
CREATE TABLE tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, cover_path TEXT, file_path TEXT, last_read_position TEXT,
  reading_percentage REAL, author TEXT, is_deleted INTEGER, description TEXT,
  create_time TEXT, update_time TEXT, rating REAL
)''');
    await db.execute('''
CREATE TABLE tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER, content TEXT, cfi TEXT, chapter TEXT, type TEXT,
  color TEXT, create_time TEXT, update_time TEXT
)''');

    await DBHelper().onUpgradeDatabase(db, 4, currentDbVersion);

    expect(await hasColumn(db, 'tb_books', 'group_id'), isTrue);
    expect(await hasColumn(db, 'tb_books', 'file_md5'), isTrue);
    expect(await hasColumn(db, 'tb_books', 'bookmark_data'), isTrue);
    expect(await hasColumn(db, 'tb_books', 'source_kind'), isTrue);
    expect(await hasColumn(db, 'tb_notes', 'reader_note'), isTrue);
    expect(await hasTable(db, 'tb_groups'), isTrue);
    final root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));
    await db.close();
  });

  test('ensureCriticalSchema repairs a broken fresh install and is idempotent',
      () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // Shape left behind by the old broken chain: full baked tb_books from
    // createBookSQL, but tb_notes without reader_note and no tb_groups.
    await db.execute(createBookSQL);
    await db.execute('''
CREATE TABLE tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER, content TEXT, cfi TEXT, chapter TEXT, type TEXT,
  color TEXT, create_time TEXT, update_time TEXT
)''');

    await DBHelper().ensureCriticalSchema(db);

    expect(await hasTable(db, 'tb_groups'), isTrue);
    expect(await hasColumn(db, 'tb_notes', 'reader_note'), isTrue);
    var root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));

    // Idempotent: running again must not throw or duplicate the root group.
    await DBHelper().ensureCriticalSchema(db);
    root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));
    await db.close();
  });

  test('ensureCriticalSchema handles a db missing tb_notes entirely',
      () async {
    // A kill during the old unawaited onCreate could commit user_version=8
    // with only tb_books created; the repair must heal it, not crash boot.
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(createBookSQL);

    await DBHelper().ensureCriticalSchema(db);

    expect(await hasTable(db, 'tb_notes'), isTrue);
    expect(await hasColumn(db, 'tb_notes', 'reader_note'), isTrue);
    expect(await hasTable(db, 'tb_groups'), isTrue);
    await db.close();
  });

  test('ensureCriticalSchema restores a lost root group row', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(createBookSQL);
    await db.execute(createNoteSQL);
    await db.execute(createGroupSQL); // table exists, but no root row

    await DBHelper().ensureCriticalSchema(db);

    final root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));
    await db.close();
  });

  test('fresh install seeds the two default themes', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DBHelper().onCreateDatabase(db, currentDbVersion);
    final themes = await db.rawQuery('SELECT id FROM tb_themes');
    expect(themes, hasLength(2));
    await db.close();
  });

  test('initDB opens a broken on-disk v8 db and repairs it (composition)',
      () async {
    final dir = await Directory.systemTemp.createTemp('db_migration_test');
    addTearDown(() => dir.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );

    // Pre-place the broken-install shape at the real production path:
    // user_version=8 with only tb_books, no tb_notes, no tb_groups.
    final dbDir = Directory('${dir.path}/databases');
    await dbDir.create(recursive: true);
    final broken = await databaseFactory
        .openDatabase('${dbDir.path}/app_database.db');
    await broken.execute(createBookSQL);
    await broken.execute('PRAGMA user_version = $currentDbVersion');
    await broken.close();

    final db = await DBHelper().initDB();
    addTearDown(DBHelper.close);

    expect(await hasTable(db, 'tb_notes'), isTrue);
    expect(await hasColumn(db, 'tb_notes', 'reader_note'), isTrue);
    expect(await hasTable(db, 'tb_groups'), isTrue);
    final root = await db.rawQuery('SELECT id FROM tb_groups WHERE id = 0');
    expect(root, hasLength(1));
  });
}
