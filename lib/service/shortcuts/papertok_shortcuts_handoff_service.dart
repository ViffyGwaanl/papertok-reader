import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/models/attachment_item.dart';
import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PapertokShortcutsHandoffService {
  PapertokShortcutsHandoffService._();

  static Future<void> sendToChat({
    required String prompt,
    required List<String> imagesBase64Jpeg,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      AnxLog.warning('shortcuts: navigator context not ready');
      return;
    }

    final container = ProviderScope.containerOf(ctx);
    final notifier = container.read(aiChatProvider.notifier);

    if (notifier.isStreaming) {
      await notifier.cancelStreaming();
    }

    final attachments = <AttachmentItem>[];
    for (final b64 in imagesBase64Jpeg.take(4)) {
      final s = b64.trim();
      if (s.isEmpty) continue;
      final bytes = Uint8List.fromList(base64Decode(s));
      attachments.add(AttachmentItem.image(bytes: bytes, base64: s));
    }

    // Start streaming; the provider persists session history.
    notifier.startStreaming(
      prompt.trim(),
      false,
      attachments: attachments.isEmpty ? null : attachments,
    );
  }
}
