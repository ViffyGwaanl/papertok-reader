import 'dart:io';

import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/receive_file/share_inbound_decider.dart';
import 'package:anx_reader/service/receive_file/share_routing_models.dart';
import 'package:anx_reader/service/receive_file/share_to_ai_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

void receiveShareIntent(WidgetRef ref) {
  final handler = ShareHandlerPlatform.instance;

  Future<void> handleShare(SharedMedia? media) async {
    AnxLog.info('share: Receive share intent called, ${media?.content}');
    if (media == null) {
      AnxLog.info('share: Receive share intent: null media');
      return;
    }

    try {
      final images = <ShareInboundImage>[];
      final files = <ShareInboundFile>[];

      final attachments = media.attachments ?? const [];
      if (attachments.isNotEmpty) {
        AnxLog.info(
          'share: Receive share intent: ${attachments.map((e) => e?.path).join(', ')}',
        );
      }

      for (final item in attachments) {
        if (item == null || item.path.isEmpty) continue;

        final filename = item.path.split(Platform.pathSeparator).last;

        if (item.type == SharedAttachmentType.image) {
          images.add(ShareInboundImage(path: item.path));
        } else {
          files.add(
            ShareInboundFile(
              path: item.path,
              filename: filename,
              kind: ShareInboundFile.classifyByFilename(filename),
            ),
          );
        }
      }

      final payload = ShareInboundPayload(
        sharedText: (media.content ?? '').trim(),
        urls: const [],
        images: images,
        files: files,
      );

      if (!payload.hasText &&
          !payload.hasUrls &&
          !payload.hasImages &&
          payload.files.isEmpty) {
        AnxLog.info('share: Receive share intent: empty payload');
        return;
      }

      final mode = _mapSharePanelMode(Prefs().sharePanelModeV1);
      final decision = ShareInboundDecider.decide(mode: mode, payload: payload);

      switch (decision.destination) {
        case ShareDestination.askUser:
          // Ask-mode UI lands later; for now fallback to auto.
          final d = ShareInboundDecider.decide(
            mode: SharePanelMode.auto,
            payload: payload,
          );
          await _applyDecision(d, payload, ref);
          return;

        case ShareDestination.bookshelf:
          final ctx = navigatorKey.currentContext;
          if (ctx == null) {
            AnxLog.warning(
                'share: navigator context not ready; dropping payload');
            return;
          }
          importBookList(
            decision.bookshelfImportFiles.map((p) => File(p)).toList(),
            ctx,
            ref,
          );
          return;

        case ShareDestination.aiChat:
          await _applyDecision(decision, payload, ref);
          return;
      }
    } finally {
      // Always reset; otherwise the plugin may replay the initial media.
      handler.resetInitialSharedMedia();
    }
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

SharePanelMode _mapSharePanelMode(String raw) {
  switch (raw) {
    case Prefs.sharePanelModeAiChat:
      return SharePanelMode.aiChat;
    case Prefs.sharePanelModeBookshelf:
      return SharePanelMode.bookshelf;
    case Prefs.sharePanelModeAsk:
      return SharePanelMode.ask;
    case Prefs.sharePanelModeAuto:
    default:
      return SharePanelMode.auto;
  }
}

Future<void> _applyDecision(
  ShareDecision decision,
  ShareInboundPayload payload,
  WidgetRef ref,
) async {
  // For Commit 1, we only support text+images for AI chat. File cards are wired
  // later when the chat UI exposes an entry point.
  final ctx = navigatorKey.currentContext;
  if (ctx == null) {
    AnxLog.warning('share: navigator context not ready; dropping payload');
    return;
  }

  // Convert ShareInboundImage -> File for existing service.
  final imageFiles = payload.images.map((e) => File(e.path)).toList();

  await ShareToAiService.sendToAiChatFromShare(
    ctx,
    sharedText: payload.sharedText,
    imageFiles: imageFiles,
  );
}
