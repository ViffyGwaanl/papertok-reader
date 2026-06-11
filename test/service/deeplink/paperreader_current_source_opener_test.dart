import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/deeplink/paperreader_current_source_opener.dart';

void main() {
  test('opens same-book cfi in the current reader', () {
    final opened = <String>[];
    var beforeOpenCount = 0;

    final handled = PaperReaderCurrentSourceOpener.tryOpen(
      uri: Uri.parse(
        'paperreader://reader/open?bookId=7&cfi=epubcfi(%2F6%2F8)',
      ),
      currentBookId: 7,
      goToCfi: (cfi) => opened.add('cfi:$cfi'),
      goToHref: (href) => opened.add('href:$href'),
      beforeOpen: () => beforeOpenCount += 1,
    );

    expect(handled, isTrue);
    expect(opened, ['cfi:epubcfi(/6/8)']);
    expect(beforeOpenCount, 1);
  });

  test('opens same-book href when cfi is absent', () {
    final opened = <String>[];

    final handled = PaperReaderCurrentSourceOpener.tryOpen(
      uri: Uri.parse(
        'paperreader://reader/open?bookId=7&href=Text%2Fch2.xhtml',
      ),
      currentBookId: 7,
      goToCfi: (cfi) => opened.add('cfi:$cfi'),
      goToHref: (href) => opened.add('href:$href'),
    );

    expect(handled, isTrue);
    expect(opened, ['href:Text/ch2.xhtml']);
  });

  test('leaves cross-book and malformed links for fallback handling', () {
    final opened = <String>[];

    final crossBookHandled = PaperReaderCurrentSourceOpener.tryOpen(
      uri: Uri.parse('paperreader://reader/open?bookId=8&cfi=epubcfi(/6/8)'),
      currentBookId: 7,
      goToCfi: opened.add,
      goToHref: opened.add,
    );
    final malformedHandled = PaperReaderCurrentSourceOpener.tryOpen(
      uri: Uri.parse('https://example.com/source'),
      currentBookId: 7,
      goToCfi: opened.add,
      goToHref: opened.add,
    );

    expect(crossBookHandled, isFalse);
    expect(malformedHandled, isFalse);
    expect(opened, isEmpty);
  });
}
