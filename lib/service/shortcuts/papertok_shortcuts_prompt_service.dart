import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/share_prompt_preset.dart';

class ShortcutsPromptResolution {
  const ShortcutsPromptResolution({
    required this.prompt,
    required this.mode,
    required this.preset,
  });

  final String prompt;
  final String mode;
  final SharePromptPreset? preset;

  bool get usedPreset => preset != null;
}

class PapertokShortcutsPromptService {
  PapertokShortcutsPromptService._();

  static const String modeOff = 'off';
  static const String modeWhenEmpty = 'when_empty';
  static const String modePrepend = 'prepend';

  static ShortcutsPromptResolution resolve(String prompt) {
    final raw = prompt.trim();
    final prefs = Prefs();
    final mode = prefs.shortcutsPromptPresetModeV1;
    final preset = _resolvePreset(prefs);
    final presetPrompt = (preset?.prompt ?? '').trim();

    if (preset == null || presetPrompt.isEmpty || mode == modeOff) {
      return ShortcutsPromptResolution(
        prompt: raw,
        mode: modeOff,
        preset: null,
      );
    }

    if (mode == modeWhenEmpty) {
      return ShortcutsPromptResolution(
        prompt: raw.isEmpty ? presetPrompt : raw,
        mode: modeWhenEmpty,
        preset: raw.isEmpty ? preset : null,
      );
    }

    final merged = [presetPrompt, raw]
        .where((e) => e.trim().isNotEmpty)
        .join('\n\n')
        .trim();

    return ShortcutsPromptResolution(
      prompt: merged,
      mode: modePrepend,
      preset: preset,
    );
  }

  static SharePromptPreset? _resolvePreset(Prefs prefs) {
    final state = prefs.sharePromptPresetsStateV2;
    final enabled = state.enabledPresets;
    if (enabled.isEmpty) return null;

    final explicitId = prefs.shortcutsPromptPresetIdV1.trim();
    if (explicitId.isNotEmpty) {
      for (final preset in enabled) {
        if (preset.id == explicitId) return preset;
      }
    }

    final lastSelected = (state.lastSelectedPresetId ?? '').trim();
    if (lastSelected.isNotEmpty) {
      for (final preset in enabled) {
        if (preset.id == lastSelected) return preset;
      }
    }

    if (enabled.length == 1) {
      return enabled.first;
    }
    return null;
  }
}
