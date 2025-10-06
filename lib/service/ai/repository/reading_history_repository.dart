import 'package:anx_reader/dao/book.dart' as book_dao;
import 'package:anx_reader/dao/reading_time.dart' as reading_time_dao;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';

class ReadingHistoryRecord {
  ReadingHistoryRecord({
    required this.book,
    required this.entry,
  });

  final Book book;
  final ReadingTime entry;

  Map<String, dynamic> toMap() {
    return {
      'bookId': book.id,
      'bookTitle': book.title,
      'author': book.author,
      'date': entry.date,
      'readingDuration': convertSeconds(entry.readingTime),
      'groupId': book.groupId,
    };
  }
}

class ReadingHistoryRepository {
  const ReadingHistoryRepository();

  Future<List<ReadingHistoryRecord>> fetchHistory({
    int? bookId,
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) async {
    final entries = await reading_time_dao.queryReadingHistory(
      bookId: bookId,
      from: from,
      to: to,
      limit: limit,
    );

    if (entries.isEmpty) {
      return const [];
    }

    final bookIds = entries.map((entry) => entry.bookId).toSet().toList();
    final books = await book_dao.selectBooksByIds(bookIds);
    final bookMap = {for (final book in books) book.id: book};

    final records = <ReadingHistoryRecord>[];
    for (final entry in entries) {
      final book = bookMap[entry.bookId];
      if (book == null) {
        continue;
      }
      records.add(ReadingHistoryRecord(book: book, entry: entry));
    }
    return records;
  }
}
