import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/providers/sync.dart';

class ReadingTimeDao extends BaseDao {
  ReadingTimeDao();

  static const String table = 'tb_reading_time';

  Future<void> insertReadingTime(ReadingTime readingTime) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await db.transaction((txn) async {
      final existing = await txn.query(
        table,
        where: 'date = ? AND book_id = ?',
        whereArgs: [today, readingTime.bookId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        final current = existing.first['reading_time'] as int? ?? 0;
        await txn.update(
          table,
          {'reading_time': current + readingTime.readingTime},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert(
          table,
          {
            'book_id': readingTime.bookId,
            'date': today,
            'reading_time': readingTime.readingTime,
          },
        );
      }
    });
  }

  Future<List<ReadingTime>> selectAllReadingTime() async {
    return queryList(
      table,
      mapper: ReadingTime.fromDb,
    );
  }

  Future<int> selectTotalReadingTime() async {
    final result = await rawQuerySingle(
      'SELECT SUM(reading_time) AS total_sum FROM $table',
      mapper: (row) => row['total_sum'] as int? ?? 0,
    );
    return result ?? 0;
  }

  Future<int> selectTotalNumberOfBook() async {
    final result = await rawQuerySingle(
      'SELECT COUNT(DISTINCT book_id) AS total_count FROM $table',
      mapper: (row) => row['total_count'] as int? ?? 0,
    );
    return result ?? 0;
  }

  Future<int> selectTotalNumberOfDate() async {
    final result = await rawQuerySingle(
      'SELECT COUNT(DISTINCT date) AS total_count FROM $table',
      mapper: (row) => row['total_count'] as int? ?? 0,
    );
    return result ?? 0;
  }

  Future<int> selectTotalNumberOfNotes() async {
    final result = await rawQuerySingle(
      'SELECT COUNT(*) AS total_count FROM tb_notes',
      mapper: (row) => row['total_count'] as int? ?? 0,
    );
    return result ?? 0;
  }

  Future<List<int>> selectReadingTimeOfWeek(DateTime dateTime) async {
    final start = dateTime.subtract(Duration(days: dateTime.weekday - 1));
    final end = start.add(const Duration(days: 6));
    final rows = await rawQueryList(
      '''
      SELECT date, SUM(reading_time) AS total_sum 
      FROM $table 
      WHERE date BETWEEN ? AND ? 
      GROUP BY date
      ''',
      arguments: [
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ],
      mapper: (row) => row,
    );

    final totals = {
      for (final row in rows)
        row['date'] as String: row['total_sum'] as int? ?? 0,
    };

    return List<int>.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final key = day.toIso8601String().substring(0, 10);
      return totals[key] ?? 0;
    });
  }

  Future<List<int>> selectReadingTimeOfMonth(DateTime dateTime) async {
    final firstDay = DateTime(dateTime.year, dateTime.month, 1);
    final lastDay = DateTime(dateTime.year, dateTime.month + 1, 0);

    final rows = await rawQueryList(
      '''
      SELECT date, SUM(reading_time) AS total_sum 
      FROM $table 
      WHERE date BETWEEN ? AND ? 
      GROUP BY date
      ''',
      arguments: [
        firstDay.toIso8601String().substring(0, 10),
        lastDay.toIso8601String().substring(0, 10),
      ],
      mapper: (row) => row,
    );

    final totals = {
      for (final row in rows)
        row['date'] as String: row['total_sum'] as int? ?? 0,
    };

    final daysInMonth = lastDay.day;
    return List<int>.generate(daysInMonth, (index) {
      final day = firstDay.add(Duration(days: index));
      final key = day.toIso8601String().substring(0, 10);
      return totals[key] ?? 0;
    });
  }

  Future<List<int>> selectReadingTimeOfYear(DateTime dateTime) async {
    final yearStart = DateTime(dateTime.year, 1, 1);
    final yearEnd = DateTime(dateTime.year, 12, 31);

    final rows = await rawQueryList(
      '''
      SELECT SUBSTR(date, 1, 7) AS month, SUM(reading_time) AS total_sum 
      FROM $table 
      WHERE date BETWEEN ? AND ? 
      GROUP BY month
      ''',
      arguments: [
        yearStart.toIso8601String().substring(0, 10),
        yearEnd.toIso8601String().substring(0, 10),
      ],
      mapper: (row) => row,
    );

    final totals = {
      for (final row in rows)
        row['month'] as String: row['total_sum'] as int? ?? 0,
    };

    return List<int>.generate(12, (index) {
      final monthKey = DateTime(dateTime.year, index + 1, 1)
          .toIso8601String()
          .substring(0, 7);
      return totals[monthKey] ?? 0;
    });
  }

  Future<List<ReadingTime>> selectReadingTimeByBookId(int bookId) {
    return queryList(
      table,
      mapper: ReadingTime.fromDb,
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<ReadingTime>> queryReadingHistory({
    int? bookId,
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final where = <String>[];
    final whereArgs = <Object?>[];

    if (bookId != null) {
      where.add('book_id = ?');
      whereArgs.add(bookId);
    }

    String? toDateString(DateTime? date) =>
        date?.toIso8601String().substring(0, 10);

    final fromStr = toDateString(from);
    final toStr = toDateString(to);

    if (fromStr != null) {
      where.add('date >= ?');
      whereArgs.add(fromStr);
    }

    if (toStr != null) {
      where.add('date <= ?');
      whereArgs.add(toStr);
    }

    return queryList(
      table,
      mapper: ReadingTime.fromDb,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : whereArgs,
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
  }

  Future<List<Map<int, int>>> selectThisWeekBooks() async {
    final monday =
        DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final rows = await rawQueryList(
      '''
      SELECT book_id, SUM(reading_time) AS total_sum 
      FROM $table 
      WHERE date >= ? 
      GROUP BY book_id 
      ORDER BY total_sum DESC
      ''',
      arguments: [monday.toIso8601String().substring(0, 10)],
      mapper: (row) => {
        (row['book_id'] as int?) ?? 0: row['total_sum'] as int? ?? 0,
      },
    );
    return rows;
  }

  Future<int> selectTotalReadingTimeByBookId(int bookId) async {
    final total = await rawQuerySingle(
      'SELECT SUM(reading_time) AS total_sum FROM $table WHERE book_id = ?',
      arguments: [bookId],
      mapper: (row) => row['total_sum'] as int? ?? 0,
    );
    return total ?? 0;
  }

  Future<List<Map<Book, int>>> selectBookReadingTimeOfDay(DateTime date) async {
    final rows = await _aggregateByBook(
      where: 'date = ?',
      whereArgs: [date.toIso8601String().substring(0, 10)],
    );
    return _attachBooks(rows);
  }

  Future<List<Map<Book, int>>> selectBookReadingTimeOfWeek(
      DateTime date) async {
    final start = date.subtract(Duration(days: date.weekday - 1));
    final end = start.add(const Duration(days: 6));
    final rows = await _aggregateByBook(
      where: 'date BETWEEN ? AND ?',
      whereArgs: [
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ],
    );
    return _attachBooks(rows);
  }

  Future<List<Map<Book, int>>> selectBookReadingTimeOfMonth(
      DateTime date) async {
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0);
    final rows = await _aggregateByBook(
      where: 'date BETWEEN ? AND ?',
      whereArgs: [
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ],
    );
    return _attachBooks(rows);
  }

  Future<List<Map<Book, int>>> selectBookReadingTimeOfYear(
      DateTime date) async {
    final start = DateTime(date.year, 1, 1);
    final end = DateTime(date.year, 12, 31);
    final rows = await _aggregateByBook(
      where: 'date BETWEEN ? AND ?',
      whereArgs: [
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ],
    );
    return _attachBooks(rows);
  }

  Future<Map<DateTime, int>> selectAllReadingTimeGroupByDay() async {
    final rows = await rawQueryList(
      '''
      SELECT date, SUM(reading_time) AS total_time 
      FROM $table 
      GROUP BY date 
      ORDER BY date ASC
      ''',
      mapper: (row) => row,
    );

    final result = <DateTime, int>{};
    for (final row in rows) {
      final date = DateTime.parse(row['date'] as String);
      result[date] = row['total_time'] as int? ?? 0;
    }
    return result;
  }

  Future<List<Map<Book, int>>> selectBookReadingTimeOfAll() async {
    final rows = await _aggregateByBook();
    return _attachBooks(rows);
  }

  Future<void> deleteReadingTimeByBookId(List<int> bookIds) async {
    if (bookIds.isEmpty) return;

    final placeholders = List.filled(bookIds.length, '?').join(',');
    await delete(
      table,
      where: 'book_id IN ($placeholders)',
      whereArgs: bookIds,
    );

    Sync().syncData(SyncDirection.both, null, trigger: SyncTrigger.auto);
  }

  Future<List<Map<String, dynamic>>> _aggregateByBook({
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT book_id, SUM(reading_time) AS total_time 
      FROM $table 
      ${where != null ? 'WHERE $where' : ''} 
      GROUP BY book_id 
      ORDER BY total_time DESC
      ''',
      whereArgs,
    );
  }

  Future<List<Map<Book, int>>> _attachBooks(
      List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((row) => row['book_id'] as int?)
        .whereType<int>()
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const [];
    }

    final books = await bookDao.selectBooksByIds(ids);
    final bookMap = {for (final book in books) book.id: book};

    final result = <Map<Book, int>>[];
    for (final row in rows) {
      final bookId = row['book_id'] as int?;
      if (bookId == null) continue;
      final book = bookMap[bookId];
      if (book == null) continue;
      result.add({book: row['total_time'] as int? ?? 0});
    }
    return result;
  }
}

final readingTimeDao = ReadingTimeDao();

@Deprecated('Use readingTimeDao.insertReadingTime instead')
Future<void> insertReadingTime(ReadingTime readingTime) =>
    readingTimeDao.insertReadingTime(readingTime);

@Deprecated('Use readingTimeDao.selectAllReadingTime instead')
Future<List<ReadingTime>> selectAllReadingTime() =>
    readingTimeDao.selectAllReadingTime();

@Deprecated('Use readingTimeDao.selectTotalReadingTime instead')
Future<int> selectTotalReadingTime() => readingTimeDao.selectTotalReadingTime();

@Deprecated('Use readingTimeDao.selectTotalNumberOfBook instead')
Future<int> selectTotalNumberOfBook() =>
    readingTimeDao.selectTotalNumberOfBook();

@Deprecated('Use readingTimeDao.selectTotalNumberOfDate instead')
Future<int> selectTotalNumberOfDate() =>
    readingTimeDao.selectTotalNumberOfDate();

@Deprecated('Use readingTimeDao.selectTotalNumberOfNotes instead')
Future<int> selectTotalNumberOfNotes() =>
    readingTimeDao.selectTotalNumberOfNotes();

@Deprecated('Use readingTimeDao.selectReadingTimeOfWeek instead')
Future<List<int>> selectReadingTimeOfWeek(DateTime dateTime) =>
    readingTimeDao.selectReadingTimeOfWeek(dateTime);

@Deprecated('Use readingTimeDao.selectReadingTimeOfMonth instead')
Future<List<int>> selectReadingTimeOfMonth(DateTime dateTime) =>
    readingTimeDao.selectReadingTimeOfMonth(dateTime);

@Deprecated('Use readingTimeDao.selectReadingTimeOfYear instead')
Future<List<int>> selectReadingTimeOfYear(DateTime dateTime) =>
    readingTimeDao.selectReadingTimeOfYear(dateTime);

@Deprecated('Use readingTimeDao.selectReadingTimeByBookId instead')
Future<List<ReadingTime>> selectReadingTimeByBookId(int bookId) =>
    readingTimeDao.selectReadingTimeByBookId(bookId);

@Deprecated('Use readingTimeDao.queryReadingHistory instead')
Future<List<ReadingTime>> queryReadingHistory({
  int? bookId,
  DateTime? from,
  DateTime? to,
  int? limit,
}) =>
    readingTimeDao.queryReadingHistory(
      bookId: bookId,
      from: from,
      to: to,
      limit: limit,
    );

@Deprecated('Use readingTimeDao.selectThisWeekBooks instead')
Future<List<Map<int, int>>> selectThisWeekBooks() =>
    readingTimeDao.selectThisWeekBooks();

@Deprecated('Use readingTimeDao.selectTotalReadingTimeByBookId instead')
Future<int> selectTotalReadingTimeByBookId(int bookId) =>
    readingTimeDao.selectTotalReadingTimeByBookId(bookId);

@Deprecated('Use readingTimeDao.selectBookReadingTimeOfDay instead')
Future<List<Map<Book, int>>> selectBookReadingTimeOfDay(DateTime date) =>
    readingTimeDao.selectBookReadingTimeOfDay(date);

@Deprecated('Use readingTimeDao.selectBookReadingTimeOfWeek instead')
Future<List<Map<Book, int>>> selectBookReadingTimeOfWeek(DateTime date) =>
    readingTimeDao.selectBookReadingTimeOfWeek(date);

@Deprecated('Use readingTimeDao.selectBookReadingTimeOfMonth instead')
Future<List<Map<Book, int>>> selectBookReadingTimeOfMonth(DateTime date) =>
    readingTimeDao.selectBookReadingTimeOfMonth(date);

@Deprecated('Use readingTimeDao.selectBookReadingTimeOfYear instead')
Future<List<Map<Book, int>>> selectBookReadingTimeOfYear(DateTime date) =>
    readingTimeDao.selectBookReadingTimeOfYear(date);

@Deprecated('Use readingTimeDao.selectAllReadingTimeGroupByDay instead')
Future<Map<DateTime, int>> selectAllReadingTimeGroupByDay() =>
    readingTimeDao.selectAllReadingTimeGroupByDay();

@Deprecated('Use readingTimeDao.selectBookReadingTimeOfAll instead')
Future<List<Map<Book, int>>> selectBookReadingTimeOfAll(DateTime date) =>
    readingTimeDao.selectBookReadingTimeOfAll();

@Deprecated('Use readingTimeDao.deleteReadingTimeByBookId instead')
Future<void> deleteReadingTimeByBookId(List<int> bookIds) =>
    readingTimeDao.deleteReadingTimeByBookId(bookIds);
