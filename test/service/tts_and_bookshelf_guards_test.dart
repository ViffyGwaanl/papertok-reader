import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/page/home_page/bookshelf_page.dart';
import 'package:papertok_reader/service/tts/tts_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsHandler.readerMediaItem', () {
    test('returns null when no reading page is mounted', () {
      // Headset play command / audio-interruption resume after the book was
      // closed used to force-unwrap epubPlayerKey.currentState and crash.
      expect(TtsHandler.readerMediaItem(), isNull);
    });
  });

  group('bookshelfCrossAxisCount', () {
    test('clamps to one column when window is narrower than a cover', () {
      expect(bookshelfCrossAxisCount(200, 260), 1);
      expect(bookshelfCrossAxisCount(0, 120), 1);
    });

    test('keeps normal division for regular widths', () {
      expect(bookshelfCrossAxisCount(390, 120), 3);
      expect(bookshelfCrossAxisCount(1280, 120), 10);
    });
  });
}
