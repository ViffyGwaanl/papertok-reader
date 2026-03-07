import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('off mode keeps incoming prompt unchanged', () {
    final prefs = Prefs();
    prefs.shortcutsPromptPresetModeV1 = 'off';

    final resolved = PapertokShortcutsPromptService.resolve('hello');

    expect(resolved.prompt, 'hello');
    expect(resolved.usedPreset, isFalse);
  });

  test('when_empty mode uses selected preset only when prompt is empty', () {
    final prefs = Prefs();
    final state = prefs.sharePromptPresetsStateV2;
    final preset = state.enabledPresets.first;

    prefs.shortcutsPromptPresetModeV1 = 'when_empty';
    prefs.shortcutsPromptPresetIdV1 = preset.id;

    final resolvedEmpty = PapertokShortcutsPromptService.resolve('   ');
    expect(resolvedEmpty.prompt, preset.prompt.trim());
    expect(resolvedEmpty.usedPreset, isTrue);

    final resolvedFilled =
        PapertokShortcutsPromptService.resolve('user prompt');
    expect(resolvedFilled.prompt, 'user prompt');
    expect(resolvedFilled.usedPreset, isFalse);
  });

  test('prepend mode prepends preset to incoming prompt', () {
    final prefs = Prefs();
    final state = prefs.sharePromptPresetsStateV2;
    final preset = state.enabledPresets.first;

    prefs.shortcutsPromptPresetModeV1 = 'prepend';
    prefs.shortcutsPromptPresetIdV1 = preset.id;

    final resolved = PapertokShortcutsPromptService.resolve('user prompt');

    expect(resolved.prompt, '${preset.prompt.trim()}\n\nuser prompt');
    expect(resolved.usedPreset, isTrue);
  });
}
