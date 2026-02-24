import 'dart:async';

import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ai_index_schema.dart';

class AiBookIndexInfo {
  const AiBookIndexInfo({
    required this.bookId,
    required this.chunkCount,
    this.embeddingModel,
    this.providerId,
    this.bookMd5,
    this.createdAt,
    this.updatedAt,
  });

  final int bookId;
  final int chunkCount;
  final String? embeddingModel;
  final String? providerId;
  final String? bookMd5;
  final int? createdAt;
  final int? updatedAt;
}

/// Independent SQLite DB for AI indexing.
///
/// It is intentionally separated from the main app database:
/// - can be rebuilt cheaply
/// - should not be synced
class AiIndexDatabase {
  AiIndexDatabase._({this.pathOverride, this.factoryOverride});

  static final AiIndexDatabase instance = AiIndexDatabase._();

  final String? pathOverride;
  final DatabaseFactory? factoryOverride;

  Database? _db;

  factory AiIndexDatabase.forTesting({
    required String path,
    DatabaseFactory? factory,
  }) {
    return AiIndexDatabase._(pathOverride: path, factoryOverride: factory);
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
  }

  Future<String> _resolvePath() async {
    if (pathOverride != null) return pathOverride!;
    final dir = await getAnxDataBasesPath();
    return p.join(dir, 'ai_index.db');
  }

  Future<Database> _open() async {
    final path = await _resolvePath();

    Future<void> onConfigure(Database db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    Future<void> onCreate(Database db, int version) async {
      await AiIndexMigrations.migrate(db, 0, version);
    }

    Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
      await AiIndexMigrations.migrate(db, oldVersion, newVersion);
    }

    // Allow tests to inject a factory.
    final factory = factoryOverride;

    // Windows/iOS use FFI in this project; keep behavior consistent.
    switch (AnxPlatform.type) {
      case AnxPlatformEnum.ios:
      case AnxPlatformEnum.windows:
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        return databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: kAiIndexDbVersion,
            onConfigure: onConfigure,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
          ),
        );
      case AnxPlatformEnum.macos:
      case AnxPlatformEnum.android:
      case AnxPlatformEnum.ohos:
        if (factory != null) {
          return factory.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: kAiIndexDbVersion,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
            ),
          );
        }
        return openDatabase(
          path,
          version: kAiIndexDbVersion,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
        );
    }
  }

  Future<AiBookIndexInfo?> getBookIndexInfo(int bookId) async {
    final db = await database;
    final rows = await db.query(
      'ai_book_index',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AiBookIndexInfo(
      bookId: (r['book_id'] as num?)?.toInt() ?? bookId,
      chunkCount: (r['chunk_count'] as num?)?.toInt() ?? 0,
      embeddingModel: r['embedding_model']?.toString(),
      providerId: r['provider_id']?.toString(),
      bookMd5: r['book_md5']?.toString(),
      createdAt: (r['created_at'] as num?)?.toInt(),
      updatedAt: (r['updated_at'] as num?)?.toInt(),
    );
  }

  Future<void> clearBook(int bookId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('ai_chunks', where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(
        'ai_book_index',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
    AnxLog.info('AiIndexDB: cleared bookId=$bookId');
  }
}
