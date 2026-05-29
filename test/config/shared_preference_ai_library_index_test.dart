import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI library index retry count defaults and clamps', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    expect(Prefs().aiLibraryIndexQueueMaxRetries, 3);

    Prefs().aiLibraryIndexQueueMaxRetries = -1;
    expect(Prefs().aiLibraryIndexQueueMaxRetries, 0);

    Prefs().aiLibraryIndexQueueMaxRetries = 99;
    expect(Prefs().aiLibraryIndexQueueMaxRetries, 10);
  });
}
