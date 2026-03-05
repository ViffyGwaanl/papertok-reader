import 'package:anx_reader/models/share_prompt_preset.dart';
import 'package:anx_reader/service/receive_file/share_to_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareToAiService preset helpers', () {
    test('autoPickSingleEnabledPreset returns preset only when exactly one enabled', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final oneEnabled = SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: [
          SharePromptPreset(
            id: 'a',
            title: 'A',
            prompt: 'p',
            enabled: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
          SharePromptPreset(
            id: 'b',
            title: 'B',
            prompt: 'p',
            enabled: false,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        ],
        lastSelectedPresetId: null,
      );

      expect(ShareToAiService.autoPickSingleEnabledPreset(oneEnabled)?.id, 'a');

      final twoEnabled = SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: [
          SharePromptPreset(
            id: 'a',
            title: 'A',
            prompt: 'p',
            enabled: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
          SharePromptPreset(
            id: 'b',
            title: 'B',
            prompt: 'p',
            enabled: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        ],
        lastSelectedPresetId: null,
      );

      expect(ShareToAiService.autoPickSingleEnabledPreset(twoEnabled), isNull);

      final noneEnabled = SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: [
          SharePromptPreset(
            id: 'a',
            title: 'A',
            prompt: 'p',
            enabled: false,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        ],
        lastSelectedPresetId: null,
      );

      expect(ShareToAiService.autoPickSingleEnabledPreset(noneEnabled), isNull);
    });

    test('initialPresetIdForDialog prefers lastSelected when enabled', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final state = SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: [
          SharePromptPreset(
            id: 'a',
            title: 'A',
            prompt: 'p',
            enabled: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
          SharePromptPreset(
            id: 'b',
            title: 'B',
            prompt: 'p',
            enabled: true,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        ],
        lastSelectedPresetId: 'b',
      );

      expect(ShareToAiService.initialPresetIdForDialog(state), 'b');

      final missing = SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: state.presets,
        lastSelectedPresetId: 'missing',
      );

      expect(ShareToAiService.initialPresetIdForDialog(missing), 'a');
    });
  });
}
