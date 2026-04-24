import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/service/bookmark/scoped_file_access.dart';

void main() {
  test('ScopedFileAccess.open returns a passthrough handle for imported books', () async {
    final book = Book.mock();
    expect(book.isInPlace, isFalse);
    final handle = await ScopedFileAccess.open(book);
    expect(handle.path, equals(book.fileFullPath));
    expect(ScopedFileAccess.activeScopedPaths.contains(handle.path), isFalse);
    await handle.dispose();
  });
}
