import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:image/image.dart' as img;

class PapertokShortcutsPendingQueue {
  PapertokShortcutsPendingQueue._();

  static const _key = 'shortcutsPendingAskV1';

  static Future<List<String>> _encodePathsToJpegBase64(
    List<String> paths,
  ) async {
    final out = <String>[];

    for (final p in paths.take(4)) {
      try {
        final bytes = await File(p).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        final normalized = _downsample(decoded, maxPixel: 2048);
        final jpg = img.encodeJpg(normalized, quality: 86);
        out.add(base64Encode(Uint8List.fromList(jpg)));
      } catch (_) {
        // Ignore missing/unreadable files.
      }
    }

    return out;
  }

  static img.Image _downsample(img.Image src, {required int maxPixel}) {
    final w = src.width;
    final h = src.height;
    final maxSide = w > h ? w : h;
    if (maxSide <= maxPixel) return src;

    final scale = maxPixel / maxSide;
    final nw = (w * scale).round();
    final nh = (h * scale).round();
    return img.copyResize(src, width: nw, height: nh);
  }

  static Future<void> _cleanupTempFiles(List<String> paths) async {
    for (final p in paths) {
      try {
        // Only delete our own temp files.
        if (!p.contains('shortcuts_ask')) continue;
        final f = File(p);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

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

      // Prefer persisted file paths (Swift handoff) to avoid huge base64 in the
      // Shortcuts process. Fallback to base64 payloads if present.
      final imagePathsRaw = obj['imagePaths'];
      final imagesRaw = obj['imagesBase64Jpeg'];

      final images = <String>[];

      if (imagePathsRaw is List) {
        final paths = imagePathsRaw
            .map((e) => (e ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

        images.addAll(await _encodePathsToJpegBase64(paths));

        // Best-effort cleanup.
        unawaited(_cleanupTempFiles(paths));
      }

      if (images.isEmpty && imagesRaw is List) {
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
