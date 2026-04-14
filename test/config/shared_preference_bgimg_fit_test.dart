import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/bgimg_fit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bgimgFit falls back to cover for invalid persisted values', () async {
    SharedPreferences.setMockInitialValues({
      'bgimgFit': 'invalid-fit-mode',
    });
    await Prefs().initPrefs();

    expect(Prefs().bgimgFit, BgimgFitEnum.cover);
  });
}
