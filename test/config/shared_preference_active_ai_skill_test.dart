import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('active AI skill normalizes legacy Seminar mode to no chat skill',
      () async {
    SharedPreferences.setMockInitialValues({
      'activeAiSkillId': 'seminar_mode',
    });
    await Prefs().initPrefs();

    expect(Prefs().activeAiSkillId, isNull);

    Prefs().activeAiSkillId = 'seminar_mode';
    expect(Prefs().activeAiSkillId, isNull);

    Prefs().activeAiSkillId = 'reading_companion';
    expect(Prefs().activeAiSkillId, 'reading_companion');
  });
}
