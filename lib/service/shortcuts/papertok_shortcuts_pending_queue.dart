import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class PapertokShortcutsPendingQueue {
  PapertokShortcutsPendingQueue._();

  static const _key = 'shortcutsPendingAskV1';

  // Protect against multiple concurrent drains (main post-frame + deeplink + channel).
  static bool _draining = false;
  static int? _lastProcessedCreatedAtMs;

  static Future<List<String>> _encodePathsToJpegBase64(
    List<String> paths,
  ) async {
    final out = <String>[];

    for (final p in paths.take(4)) {
      try {
        final bytes = await File(p).readAsBytes();
        if (bytes.isEmpty) continue;

        // Swift handoff writes already-normalized JPEG files.
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
          out.add(base64Encode(bytes));
          continue;
        }

        // Fallback for unexpected formats.
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

  static const MethodChannel _native = MethodChannel(
    'papertok_reader/pending_ask',
  );

  static Future<String?> _consumeNativePending() async {
    if (!Platform.isIOS) return null;
    try {
      final s = await _native.invokeMethod<String>('consume');
      return (s == null || s.trim().isEmpty) ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> tryDrain() async {
    if (_draining) return;
    _draining = true;

    try {
      var raw = Prefs().prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) {
        // If the AppIntent ran out-of-process, it may have persisted payload
        // to a native suite; consume it via MethodChannel.
        raw = await _consumeNativePending();
        if (raw != null && raw.trim().isNotEmpty) {
          Prefs().prefs.setString(_key, raw);
        }
      }

      if (raw == null || raw.trim().isEmpty) return;

      final obj = jsonDecode(raw);
      if (obj is! Map) return;

      final prompt = (obj['prompt'] ?? '').toString();
      final createdAtMsRaw = obj['createdAtMs'];
      final createdAtMs =
          (createdAtMsRaw is num) ? createdAtMsRaw.toInt() : null;

      if (createdAtMs != null && _lastProcessedCreatedAtMs == createdAtMs) {
        // Already processed in this process; avoid duplicate sends.
        await Prefs().prefs.remove(_key);
        return;
      }

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

      if (prompt.trim().isEmpty && images.isEmpty) {
        AnxLog.warning('shortcuts: pending ask empty, dropped');
        await Prefs().prefs.remove(_key);
        return;
      }

      // Mark as processed for this process to reduce duplicates if multiple drains race.
      _lastProcessedCreatedAtMs = createdAtMs;

      AnxLog.info(
        'shortcuts: draining pending ask (promptLen=${prompt.trim().length}, images=${images.length})',
      );

      // Ensure the AI tab is visible before sending.
      await PapertokAiChatNavigator.show();

      // Best-effort: give navigation/tab switch a moment.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final ok = await PapertokShortcutsHandoffService.sendToChat(
        prompt: prompt,
        imagesBase64Jpeg: images,
      );

      if (!ok) {
        // Keep pending payload for the next drain attempt.
        AnxLog.warning('shortcuts: handoff sendToChat failed; will retry');
        Timer(const Duration(milliseconds: 250), () {
          unawaited(tryDrain());
        });
        return;
      }

      // Clear only after we successfully started streaming.
      await Prefs().prefs.remove(_key);
    } catch (e, st) {
      AnxLog.warning('shortcuts: drain pending failed: $e', e, st);
    } finally {
      _draining = false;
    }
  }
}
