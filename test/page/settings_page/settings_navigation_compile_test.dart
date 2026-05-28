import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/page/home_page/settings_page.dart';
import 'package:papertok_reader/page/settings_page/ai.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';

void main() {
  test('AI settings navigation widgets compile', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(const AISettings(), isA<AISettings>());
    expect(const ReviewInboxPage(), isA<ReviewInboxPage>());
  });
}
