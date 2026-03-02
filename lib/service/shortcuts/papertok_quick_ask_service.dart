import 'dart:async';

import 'package:anx_reader/service/ai/index.dart';
import 'package:langchain_core/chat_models.dart';

class PapertokQuickAskService {
  PapertokQuickAskService._();

  static Future<String> send({
    required String prompt,
    required List<String> imagesBase64Jpeg,
    Duration timeout = const Duration(minutes: 3),
    bool allowPartialOnTimeout = false,
  }) async {
    if (imagesBase64Jpeg.length > 4) {
      throw StateError('At most 4 images are supported');
    }

    final parts = <ChatMessageContent>[];
    final p = prompt.trim();
    if (p.isNotEmpty) {
      parts.add(ChatMessageContent.text(p));
    }

    for (final b64 in imagesBase64Jpeg) {
      final s = b64.trim();
      if (s.isEmpty) continue;
      parts.add(
        ChatMessageContent.image(
          data: s,
          mimeType: 'image/jpeg',
        ),
      );
    }

    if (parts.isEmpty) {
      throw StateError('Both prompt and images are empty');
    }

    final content =
        parts.length == 1 ? parts.first : ChatMessageContent.multiModal(parts);

    final messages = <ChatMessage>[ChatMessage.human(content)];

    final stream = aiGenerateStream(
      messages,
      regenerate: false,
      useAgent: false,
    );

    if (!allowPartialOnTimeout) {
      final aggregated = await stream.last.timeout(timeout);
      return _stripThinkBlock(aggregated);
    }

    // Best-effort: Shortcuts/AppIntents can be interrupted if the network call
    // takes too long. Return the latest aggregated text we have so far.
    var latest = '';
    final completer = Completer<String>();

    late final StreamSubscription<String> sub;
    sub = stream.listen(
      (s) {
        latest = s;
      },
      onError: (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(latest);
        }
      },
      cancelOnError: true,
    );

    Timer(timeout, () async {
      if (completer.isCompleted) return;
      await sub.cancel();
      completer.complete(latest);
    });

    final aggregated = await completer.future;
    final out = _stripThinkBlock(aggregated);
    if (out.isNotEmpty) return out;

    return '请求未在设定时间内完成。建议打开 Papertok Reader 查看或重试。';
  }

  static String _stripThinkBlock(String s) {
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>\n?');
    return s.replaceAll(thinkRegex, '').trim();
  }
}
