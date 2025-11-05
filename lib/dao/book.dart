import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  Future<int> save(Book book) async {
    if (book.id != -1) {
      await updateBook(book);
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book) => save(book);

  Future<void> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    await update(
      table,
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<List<Book>> selectBooks({bool includeDeleted = true}) {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectNotDeleteBooks() {
    return selectBooks(includeDeleted: false);
  }

  Future<Book> selectBookById(int id) async {
    final book = await querySingle(
      table,
      mapper: Book.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (book == null) {
      throw StateError('Book with id $id not found');
    }
    return book;
  }

  Future<List<String>> getCurrentBooks() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.filePath).toList(growable: false);
  }

  Future<List<String>> getCurrentCover() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.coverPath).toList(growable: false);
  }

  Future<List<Book>> selectAllBooks() {
    return selectBooks();
  }

  Future<Book?> getBookByMd5(String md5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'file_md5 = ?',
      whereArgs: [md5],
    );
  }

  Future<List<Book>> searchBooks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    return queryList(
      table,
      mapper: Book.fromDb,
      where: 'is_deleted = 0 AND (title LIKE ? OR author LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectBooksByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    return rawQueryList(
      'SELECT * FROM $table WHERE is_deleted = 0 AND id IN ($placeholders)',
      arguments: ids,
      mapper: Book.fromDb,
    );
  }

  Future<void> updateBookMd5(int bookId, String md5) {
    return update(
      table,
      {
        'file_md5': md5,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Book>> getBooksWithoutMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (file_md5 IS NULL OR file_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }
}

final bookDao = BookDao();

@Deprecated('Use bookDao.save instead')
Future<int> insertBook(Book book) => bookDao.insertBook(book);

@Deprecated('Use bookDao.selectBooks instead')
Future<List<Book>> selectBooks() => bookDao.selectBooks();

@Deprecated('Use bookDao.selectNotDeleteBooks instead')
Future<List<Book>> selectNotDeleteBooks() => bookDao.selectNotDeleteBooks();

@Deprecated('Use bookDao.updateBook instead')
Future<void> updateBook(Book book) => bookDao.updateBook(book);

@Deprecated('Use bookDao.selectBookById instead')
Future<Book> selectBookById(int id) => bookDao.selectBookById(id);

@Deprecated('Use bookDao.getCurrentBooks instead')
Future<List<String>> getCurrentBooks() => bookDao.getCurrentBooks();

@Deprecated('Use bookDao.getCurrentCover instead')
Future<List<String>> getCurrentCover() => bookDao.getCurrentCover();

@Deprecated('Use bookDao.selectAllBooks instead')
Future<List<Book>> selectAllBooks() => bookDao.selectAllBooks();

@Deprecated('Use bookDao.getBookByMd5 instead')
Future<Book?> getBookByMd5(String md5) => bookDao.getBookByMd5(md5);

@Deprecated('Use bookDao.searchBooks instead')
Future<List<Book>> searchBooks(String keyword) => bookDao.searchBooks(keyword);

@Deprecated('Use bookDao.selectBooksByIds instead')
Future<List<Book>> selectBooksByIds(List<int> ids) =>
    bookDao.selectBooksByIds(ids);

@Deprecated('Use bookDao.updateBookMd5 instead')
Future<void> updateBookMd5(int bookId, String md5) =>
    bookDao.updateBookMd5(bookId, md5);

@Deprecated('Use bookDao.getBooksWithoutMd5 instead')
Future<List<Book>> getBooksWithoutMd5() => bookDao.getBooksWithoutMd5();
