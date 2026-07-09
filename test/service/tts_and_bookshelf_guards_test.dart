import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/page/home_page/bookshelf_page.dart';
import 'package:papertok_reader/service/tts/tts_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // TtsHandler's constructor reads Prefs and configures the audio
    // session; stub both so the real singleton can be built.
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    for (final channel in const [
      MethodChannel('com.ryanheise.audio_session'),
      MethodChannel('com.ryanheise.av_audio_session'),
      MethodChannel('com.ryanheise.android_audio_manager'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
    }
  });

  group('TtsHandler.readerMediaItem', () {
    test('returns null when no reading page is mounted', () {
      // Headset play command / audio-interruption resume after the book was
      // closed used to force-unwrap epubPlayerKey.currentState and crash.
      expect(TtsHandler.readerMediaItem(), isNull);
    });
  });

  group('TtsHandler.play', () {
    test('completes without crashing when no book is open', () async {
      // Exercises the real play() entry point (the path headset commands
      // and interruption-resume take), not just the helper.
      await expectLater(TtsHandler().play(), completes);
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
