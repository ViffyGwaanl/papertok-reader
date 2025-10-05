import 'package:anx_reader/dao/book.dart' as book_dao;
import 'package:anx_reader/models/book.dart';

class BookSearchResult {
  BookSearchResult(this.book);

  final Book book;

  Map<String, dynamic> toMap() {
    return {
      'bookId': book.id,
      'title': book.title,
      'author': book.author,
      'description': book.description,
      'readingPercentage': book.readingPercentage,
      'lastReadPosition': book.lastReadPosition,
      'groupId': book.groupId,
      'updatedAt': book.updateTime.toIso8601String(),
      'isDeleted': book.isDeleted,
    };
  }
}

class BooksRepository {
  const BooksRepository();

  Future<List<BookSearchResult>> searchBooks({
    String? keyword,
    int? groupId,
    bool includeDeleted = false,
    int limit = 10,
  }) async {
    final query = keyword?.trim() ?? '';

    List<Book> books;
    if (query.isEmpty) {
      books = await book_dao.selectBooks();
    } else {
      books = await book_dao.searchBooks(query);
    }

    if (!includeDeleted) {
      books = books.where((book) => !book.isDeleted).toList();
    }

    if (groupId != null) {
      books = books.where((book) => book.groupId == groupId).toList();
    }

    final sliced = books.take(limit).toList();
    return sliced.map(BookSearchResult.new).toList();
  }
}
