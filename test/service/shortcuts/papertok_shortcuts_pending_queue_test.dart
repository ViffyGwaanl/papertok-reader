import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_pending_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('stageRawPayloadForRetry persists payload for later drain attempts', () {
    final payload = jsonEncode({
      'requestId': 'req-1',
      'prompt': 'hello from native pending',
      'imagesBase64Jpeg': <String>[],
      'createdAtMs': 123,
    });

    PapertokShortcutsPendingQueue.stageRawPayloadForRetry(payload);

    expect(Prefs().prefs.getString('shortcutsPendingAskV1'), payload);
  });

  test('handled request ids are persisted for dedupe', () {
    expect(PapertokShortcutsPendingQueue.isRequestIdHandled('req-1'), isFalse);

    PapertokShortcutsPendingQueue.markRequestIdHandled('req-1');

    expect(PapertokShortcutsPendingQueue.isRequestIdHandled('req-1'), isTrue);
    expect(
      Prefs().prefs.getString('shortcutsLastHandledRequestIdV1'),
      'req-1',
    );
  });
}
