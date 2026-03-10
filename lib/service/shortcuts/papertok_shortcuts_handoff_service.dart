import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/models/attachment_item.dart';
import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_prompt_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PapertokShortcutsHandoffService {
  PapertokShortcutsHandoffService._();

  static Future<bool> sendToChat({
    required String prompt,
    required List<String> imagesBase64Jpeg,
    List<AttachmentItem> textFileAttachments = const [],
    bool? startNewConversation,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      AnxLog.warning('shortcuts: navigator context not ready');
      return false;
    }

    final container = ProviderScope.containerOf(ctx);
    final notifier = container.read(aiChatProvider.notifier);

    if (notifier.isStreaming) {
      await notifier.cancelStreaming();
    }

    final shouldStartNewConversation = startNewConversation ??
        (Prefs().shortcutsSendMessagePresentationV1 == 'new');
    if (shouldStartNewConversation) {
      notifier.beginFreshConversation(container);
    }

    final attachments = <AttachmentItem>[];

    for (final a in textFileAttachments) {
      if (a.type != AttachmentType.textFile) continue;
      final text = (a.text ?? '').trim();
      if (text.isEmpty) continue;
      attachments.add(a);
    }

    for (final b64
        in imagesBase64Jpeg.take(Prefs().aiChatImageAttachmentMaxCountV1)) {
      final s = b64.trim();
      if (s.isEmpty) continue;
      final bytes = Uint8List.fromList(base64Decode(s));
      attachments.add(AttachmentItem.image(bytes: bytes, base64: s));
    }

    final resolved = PapertokShortcutsPromptService.resolve(prompt);

    // Start streaming; the provider persists session history.
    notifier.startStreaming(
      resolved.prompt,
      false,
      attachments: attachments.isEmpty ? null : attachments,
    );

    return true;
  }
}
