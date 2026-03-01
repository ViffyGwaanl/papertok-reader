import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/receive_file/share_to_ai_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

void receiveShareIntent(WidgetRef ref) {
  final handler = ShareHandlerPlatform.instance;

  // receive sharing intent
  Future<void> handleShare(SharedMedia? media) async {
    AnxLog.info('share: Receive share intent called, ${media?.content}');
    if (media == null ||
        media.attachments == null ||
        media.attachments!.isEmpty) {
      AnxLog.info('share: Receive share intent: no media or empty');
      return;
    }
    AnxLog.info(
        'share: Receive share intent: ${media.attachments!.map((e) => e?.path).join(', ')}');

    final imageFiles = <File>[];
    final otherFiles = <File>[];

    for (final item in media.attachments!) {
      if (item == null || item.path.isEmpty) continue;
      final f = File(item.path);

      if (item.type == SharedAttachmentType.image) {
        imageFiles.add(f);
      } else {
        otherFiles.add(f);
      }
    }

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final prompt = (media.content ?? '').trim();

    if (Prefs().shareSheetAskPapertokEnabledV1 && imageFiles.isNotEmpty) {
      await ShareToAiService.askPapertokFromShare(
        ctx,
        prompt: prompt,
        imageFiles: imageFiles,
      );
      handler.resetInitialSharedMedia();
      return;
    }

    // Default: treat as book import.
    final files = [...otherFiles, ...imageFiles];
    importBookList(files, ctx, ref);
    handler.resetInitialSharedMedia();
  }

  handler.sharedMediaStream.listen((SharedMedia media) {
    handleShare(media);
  }, onError: (err) {
    AnxLog.severe('share: Receive share intent');
  });

  handler.getInitialSharedMedia().then((media) {
    handleShare(media);
  }, onError: (err) {
    AnxLog.severe('share: Receive share intent');
  });
}
