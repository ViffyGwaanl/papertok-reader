import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy readingInfo prefs migrate into section-based model', () async {
    SharedPreferences.setMockInitialValues({
      'readingInfo': jsonEncode({
        'headerLeft': 'chapterTitle',
        'headerCenter': 'none',
        'headerRight': 'time',
        'footerLeft': 'batteryAndTime',
        'footerCenter': 'chapterProgress',
        'footerRight': 'bookProgress',
      }),
      'pageHeaderMargin': 12.0,
      'pageFooterMargin': 18.0,
    });
    await Prefs().initPrefs();

    final readingInfo = Prefs().readingInfo;

    expect(readingInfo.header.left, ReadingInfoEnum.chapterTitle);
    expect(readingInfo.header.center, ReadingInfoEnum.none);
    expect(readingInfo.header.right, ReadingInfoEnum.time);
    expect(readingInfo.header.verticalMargin, 12.0);

    expect(readingInfo.footer.left, ReadingInfoEnum.batteryAndTime);
    expect(readingInfo.footer.center, ReadingInfoEnum.chapterProgress);
    expect(readingInfo.footer.right, ReadingInfoEnum.bookProgress);
    expect(readingInfo.footer.verticalMargin, 18.0);
  });
}
