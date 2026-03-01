import 'dart:async';

import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';
import 'package:langchain_core/chat_models.dart';

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
      case 'sendMessage':
        return _sendMessage(call.arguments);
      default:
        throw PlatformException(
          code: 'not_implemented',
          message: 'Unknown method: ${call.method}',
        );
    }
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

    final images = <String>[];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        final s = (item ?? '').toString().trim();
        if (s.isNotEmpty) images.add(s);
      }
    }

    if (images.length > 4) {
      throw PlatformException(
        code: 'too_many_images',
        message: 'At most 4 images are supported',
      );
    }

    if (prompt.isEmpty && images.isEmpty) {
      throw PlatformException(
        code: 'empty_input',
        message: 'Both prompt and images are empty',
      );
    }

    // Build a single multimodal user message.
    final parts = <ChatMessageContent>[];
    if (prompt.isNotEmpty) {
      parts.add(ChatMessageContent.text(prompt));
    }
    for (final b64 in images) {
      parts.add(
        ChatMessageContent.image(
          data: b64,
          mimeType: 'image/jpeg',
        ),
      );
    }

    final content =
        parts.length == 1 ? parts.first : ChatMessageContent.multiModal(parts);

    final messages = <ChatMessage>[ChatMessage.human(content)];

    try {
      final stream = aiGenerateStream(
        messages,
        regenerate: false,
        useAgent: false,
      );

      // We only need the final aggregated payload.
      final aggregated = await stream.last.timeout(
        const Duration(minutes: 3),
      );

      return _stripThinkBlock(aggregated);
    } catch (e, st) {
      AnxLog.warning('shortcuts: sendMessage failed: $e', e, st);
      throw PlatformException(
        code: 'ai_failed',
        message: e.toString(),
      );
    }
  }

  static String _stripThinkBlock(String s) {
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>\n?');
    return s.replaceAll(thinkRegex, '').trim();
  }
}
