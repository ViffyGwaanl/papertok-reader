import 'dart:async';

import 'package:anx_reader/service/shortcuts/papertok_quick_ask_service.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';

/// iOS App Intents -> Flutter bridge.
///
/// The Swift side hosts a headless FlutterEngine and invokes this channel.
/// We deliberately reuse the existing LangChain-based chat stack:
/// - same provider config & model selection (Prefs)
/// - same multimodal representation (base64 JPEG)
///
/// Note: we run in non-agent mode for safety and determinism (no tool calls).
class PapertokShortcutsChannel {
  PapertokShortcutsChannel._();

  static const MethodChannel _channel = MethodChannel(
    'papertok_reader/shortcuts',
  );

  static void register() {
    _channel.setMethodCallHandler(_handle);
  }

  static Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'ping':
        return 'ok';
      case 'enqueueAsk':
        return _enqueueAsk(call.arguments);
      case 'sendMessage':
        return _sendMessage(call.arguments);
      default:
        throw PlatformException(
          code: 'not_implemented',
          message: 'Unknown method: ${call.method}',
        );
    }
  }

  static Future<String> _enqueueAsk(Object? rawArgs) async {
    if (rawArgs is! Map) {
      throw PlatformException(
        code: 'bad_args',
        message: 'Expected Map arguments',
      );
    }

    final prompt = (rawArgs['prompt'] ?? '').toString().trim();
    final imagesRaw = rawArgs['imagesBase64'];

    final images = <String>[];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        final s = (item ?? '').toString().trim();
        if (s.isNotEmpty) images.add(s);
      }
    }

    // Fire-and-forget: the heavy work runs in-app, not inside Shortcuts.
    unawaited(
      PapertokShortcutsHandoffService.openChatAndSend(
        prompt: prompt,
        imagesBase64Jpeg: images,
      ),
    );

    return 'queued';
  }

  static Future<String> _sendMessage(Object? rawArgs) async {
    if (rawArgs is! Map) {
      throw PlatformException(
        code: 'bad_args',
        message: 'Expected Map arguments',
      );
    }

    final prompt = (rawArgs['prompt'] ?? '').toString().trim();
    final imagesRaw = rawArgs['imagesBase64'];
    final timeoutSecRaw = rawArgs['timeoutSeconds'];

    final images = <String>[];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        final s = (item ?? '').toString().trim();
        if (s.isNotEmpty) images.add(s);
      }
    }

    final timeoutSeconds =
        (timeoutSecRaw is num) ? timeoutSecRaw.toInt().clamp(5, 180) : 25;

    try {
      return await PapertokQuickAskService.send(
        prompt: prompt,
        imagesBase64Jpeg: images,
        timeout: Duration(seconds: timeoutSeconds),
        allowPartialOnTimeout: true,
      );
    } catch (e, st) {
      AnxLog.warning('shortcuts: sendMessage failed: $e', e, st);
      throw PlatformException(
        code: 'ai_failed',
        message: e.toString(),
      );
    }
  }
}
