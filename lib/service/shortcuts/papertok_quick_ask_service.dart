import 'dart:async';

import 'package:anx_reader/service/ai/index.dart';
import 'package:langchain_core/chat_models.dart';

class PapertokQuickAskService {
  PapertokQuickAskService._();

  static Future<String> send({
    required String prompt,
    required List<String> imagesBase64Jpeg,
    Duration timeout = const Duration(minutes: 3),
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

    final aggregated = await stream.last.timeout(timeout);
    return _stripThinkBlock(aggregated);
  }

  static String _stripThinkBlock(String s) {
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>\n?');
    return s.replaceAll(thinkRegex, '').trim();
  }
}
