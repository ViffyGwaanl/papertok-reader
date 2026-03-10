import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

class PapertokShortcutsPendingQueue {
  PapertokShortcutsPendingQueue._();

  static const _key = 'shortcutsPendingAskV1';
  static const _lastHandledRequestIdKey = 'shortcutsLastHandledRequestIdV1';

  // Protect against multiple concurrent drains (main post-frame + deeplink + channel).
  static bool _draining = false;

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
    for (final raw in paths) {
      try {
        final file = File(raw);
        if (!await file.exists()) continue;

        final canon = await _canonicalize(raw);
        final marker = '${p.separator}shortcuts_ask${p.separator}';

        final idx = canon.indexOf(marker);
        final idx2 = idx < 0 ? canon.indexOf('/shortcuts_ask/') : idx;
        final cut = idx >= 0
            ? idx + marker.length - 1
            : (idx2 >= 0 ? idx2 + '/shortcuts_ask/'.length - 1 : -1);
        if (cut < 0) continue;

        final allowRoot = canon.substring(0, cut);
        if (!_isWithin(allowRoot, canon)) continue;

        await file.delete();
      } catch (_) {
        // ignore
      }
    }
  }

  static Future<String> _canonicalize(String path) async {
    try {
      return await File(path).resolveSymbolicLinks();
    } catch (_) {
      return p.normalize(path);
    }
  }

  static bool _isWithin(String root, String path) {
    try {
      return p.isWithin(root, path) || root == path;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void stageRawPayloadForRetry(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return;
    if (Prefs().prefs.getString(_key) != normalized) {
      Prefs().prefs.setString(_key, normalized);
    }
  }

  @visibleForTesting
  static bool isRequestIdHandled(String requestId) {
    return requestId.trim().isNotEmpty &&
        Prefs().prefs.getString(_lastHandledRequestIdKey) == requestId.trim();
  }

  @visibleForTesting
  static void markRequestIdHandled(String requestId) {
    final normalized = requestId.trim();
    if (normalized.isEmpty) return;
    Prefs().prefs.setString(_lastHandledRequestIdKey, normalized);
  }

  static void enqueue({
    required String prompt,
    required List<String> imagesBase64Jpeg,
  }) {
    try {
      final payload = <String, dynamic>{
        'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
        'prompt': prompt,
        'imagesBase64Jpeg': imagesBase64Jpeg,
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      };

      stageRawPayloadForRetry(jsonEncode(payload));
    } catch (e, st) {
      AnxLog.warning('shortcuts: enqueue pending failed: $e', e, st);
    }
  }

  static const MethodChannel _native = MethodChannel(
    'papertok_reader/pending_ask',
  );

  static Future<String?> _readPendingFileBestEffort() async {
    if (!Platform.isIOS) return null;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/shortcuts_ask/pending.json');
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      final s = raw.trim();
      if (s.isEmpty) return null;

      // Remove after we successfully read it (best-effort cleanup).
      try {
        await file.delete();
      } catch (_) {
        // ignore
      }

      return s;
    } catch (_) {
      return null;
    }
  }

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
      // iOS: always prefer native consume (App Group container).
      var raw = await _consumeNativePending();

      raw ??= Prefs().prefs.getString(_key);

      if (raw == null || raw.trim().isEmpty) {
        // If the AppIntent ran out-of-process, it may have persisted payload
        // to a temp file. Prefer file-based handoff to avoid UserDefaults issues.
        raw = await _readPendingFileBestEffort();
      }

      if (raw == null || raw.trim().isEmpty) return;

      // Stage the raw payload into SharedPreferences before any routing/handoff.
      // This prevents cold-start/native-consume payloads from being lost if the
      // Flutter side is not ready yet or sendToChat fails and needs a retry.
      stageRawPayloadForRetry(raw);

      final obj = jsonDecode(raw);
      if (obj is! Map) return;

      final requestId = (obj['requestId'] ?? '').toString().trim();
      final prompt = (obj['prompt'] ?? '').toString();
      // createdAtMs is kept in payload for observability/debugging only.

      // Prefer persisted file paths (Swift handoff) to avoid huge base64 in the
      // Shortcuts process. Fallback to base64 payloads if present.
      final imagePathsRaw = obj['imagePaths'];
      final imagesRaw = obj['imagesBase64Jpeg'];

      if (isRequestIdHandled(requestId)) {
        AnxLog.info(
            'shortcuts: skip duplicate pending ask requestId=$requestId');
        await Prefs().prefs.remove(_key);
        if (imagePathsRaw is List) {
          final paths = imagePathsRaw
              .map((e) => (e ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
          unawaited(_cleanupTempFiles(paths));
        }
        return;
      }

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
      markRequestIdHandled(requestId);
      await Prefs().prefs.remove(_key);
    } catch (e, st) {
      AnxLog.warning('shortcuts: drain pending failed: $e', e, st);
    } finally {
      _draining = false;
    }
  }
}
