import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:sqflite/sqflite.dart';

class AiLibraryIndexQueueRepository {
  AiLibraryIndexQueueRepository({AiIndexDatabase? database})
      : _db = database ?? AiIndexDatabase.instance;

  final AiIndexDatabase _db;

  Future<AiLibraryIndexJob> enqueueBook(int bookId,
      {int maxRetries = 1}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _db.database;

    // Ensure a row exists in ai_book_index so foreign keys work.
    await db.insert(
      'ai_book_index',
      {
        'book_id': bookId,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final id = await db.insert('ai_index_jobs', {
      'book_id': bookId,
      'status': AiLibraryIndexJob.statusToDb(AiLibraryIndexJobStatus.queued),
      'retry_count': 0,
      'max_retries': maxRetries,
      'progress': 0,
      'created_at': now,
      'updated_at': now,
    });

    return (await getJob(id))!;
  }

  Future<AiLibraryIndexJob?> getJob(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'ai_index_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _map(rows.first);
  }

  Future<List<AiLibraryIndexJob>> listJobs() async {
    final db = await _db.database;
    final rows = await db.query(
      'ai_index_jobs',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(_map).toList(growable: false);
  }

  Future<List<AiLibraryIndexJob>> listRunnableJobs() async {
    final db = await _db.database;
    final rows = await db.query(
      'ai_index_jobs',
      where: 'status IN (?, ?)',
      whereArgs: [
        AiLibraryIndexJob.statusToDb(AiLibraryIndexJobStatus.queued),
        AiLibraryIndexJob.statusToDb(AiLibraryIndexJobStatus.running),
      ],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(_map).toList(growable: false);
  }

  Future<AiLibraryIndexJob> updateJob(
    int id, {
    AiLibraryIndexJobStatus? status,
    int? retryCount,
    double? progress,
    String? currentChapterHref,
    String? currentChapterTitle,
    String? lastError,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'updated_at': now,
    };
    if (status != null) {
      values['status'] = AiLibraryIndexJob.statusToDb(status);
    }
    if (retryCount != null) values['retry_count'] = retryCount;
    if (progress != null) values['progress'] = progress;
    if (currentChapterHref != null) {
      values['current_chapter_href'] = currentChapterHref;
    }
    if (currentChapterTitle != null) {
      values['current_chapter_title'] = currentChapterTitle;
    }
    if (lastError != null) values['last_error'] = lastError;

    await db.update('ai_index_jobs', values, where: 'id = ?', whereArgs: [id]);
    return (await getJob(id))!;
  }

  Future<void> deleteJob(int id) async {
    final db = await _db.database;
    await db.delete('ai_index_jobs', where: 'id = ?', whereArgs: [id]);
  }

  AiLibraryIndexJob _map(Map<String, Object?> r) {
    final id = (r['id'] as num?)?.toInt() ?? 0;
    final bookId = (r['book_id'] as num?)?.toInt() ?? 0;
    final statusRaw = r['status']?.toString() ?? 'failed';
    return AiLibraryIndexJob(
      id: id,
      bookId: bookId,
      status: AiLibraryIndexJob.statusFromDb(statusRaw),
      retryCount: (r['retry_count'] as num?)?.toInt() ?? 0,
      maxRetries: (r['max_retries'] as num?)?.toInt() ?? 1,
      progress: (r['progress'] as num?)?.toDouble() ?? 0,
      currentChapterHref: r['current_chapter_href']?.toString(),
      currentChapterTitle: r['current_chapter_title']?.toString(),
      lastError: r['last_error']?.toString(),
      createdAt: (r['created_at'] as num?)?.toInt(),
      updatedAt: (r['updated_at'] as num?)?.toInt(),
    );
  }
}
