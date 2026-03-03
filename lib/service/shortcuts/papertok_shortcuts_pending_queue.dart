import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';

class PapertokShortcutsPendingQueue {
  PapertokShortcutsPendingQueue._();

  static const _key = 'shortcutsPendingAskV1';

  static void enqueue({
    required String prompt,
    required List<String> imagesBase64Jpeg,
  }) {
    try {
      final payload = <String, dynamic>{
        'prompt': prompt,
        'imagesBase64Jpeg': imagesBase64Jpeg,
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      };

      Prefs().prefs.setString(_key, jsonEncode(payload));
    } catch (e, st) {
      AnxLog.warning('shortcuts: enqueue pending failed: $e', e, st);
    }
  }

  static Future<void> tryDrain() async {
    final raw = Prefs().prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return;

      final prompt = (obj['prompt'] ?? '').toString();
      final imagesRaw = obj['imagesBase64Jpeg'];

      final images = <String>[];
      if (imagesRaw is List) {
        for (final item in imagesRaw) {
          final s = (item ?? '').toString().trim();
          if (s.isNotEmpty) images.add(s);
        }
      }

      // Clear before running to avoid loops.
      await Prefs().prefs.remove(_key);

      await PapertokShortcutsHandoffService.sendToChat(
        prompt: prompt,
        imagesBase64Jpeg: images,
      );
    } catch (e, st) {
      AnxLog.warning('shortcuts: drain pending failed: $e', e, st);
    }
  }
}
