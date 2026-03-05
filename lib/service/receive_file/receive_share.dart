import 'dart:io';

import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/receive_file/share_inbound_decider.dart';
import 'package:anx_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:anx_reader/service/receive_file/share_inbox_diagnostics.dart';
import 'package:anx_reader/service/receive_file/share_inbox_paths.dart';
import 'package:anx_reader/service/receive_file/share_routing_models.dart';
import 'package:anx_reader/service/receive_file/share_safe_import.dart';
import 'package:anx_reader/service/receive_file/share_to_ai_service.dart';
import 'package:anx_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
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

      final allPaths = <String>[
        ...payload.images.map((e) => e.path),
        ...payload.files.map((e) => e.path),
      ];

      ShareInboxCleanupService.recordKnownRootsFromPaths(allPaths);

      final modeRaw = Prefs().sharePanelModeV1;
      final mode = _mapSharePanelMode(modeRaw);
      final decision = ShareInboundDecider.decide(mode: mode, payload: payload);

      final eventIds = <String>[];
      for (final p in allPaths) {
        final info = ShareInboxPaths.tryParse(p);
        if (info != null) eventIds.add(info.eventId);
      }

      ShareInboxDiagnosticsStore.append(
        ShareInboundEvent(
          atMs: DateTime.now().millisecondsSinceEpoch,
          source: 'share',
          mode: modeRaw,
          destination: decision.destination.name,
          textLen: payload.sharedText.length,
          images: payload.images.length,
          files: payload.files.length,
          textFiles: payload.textFiles.length,
          docxFiles: payload.docxFiles.length,
          bookshelfFiles: payload.bookshelfFiles.length,
          otherFiles: payload.otherFiles.length,
          eventIds: eventIds,
          cleanupStatus: 'pending',
        ),
      );

      switch (decision.destination) {
        case ShareDestination.askUser:
          await _showAskThenRoute(payload, ref);
          return;

        case ShareDestination.bookshelf:
          final ctx = await _waitForNavigatorContext();
          if (ctx == null) {
            AnxLog.warning(
                'share: navigator context not ready; dropping payload');
            return;
          }
          final importFiles = await ShareSafeImport.prepareImportFiles(
            decision.bookshelfImportFiles,
          );

          if (importFiles.isEmpty) return;

          importBookList(importFiles, ctx, ref);

          if (Prefs().sharePanelCleanupAfterUseV1) {
            // Best-effort: cleanup empty event dirs after import (import deletes files).
            Future<void>.delayed(const Duration(seconds: 2), () {
              ShareInboxCleanupService.cleanupEventDirsIfSafe(
                eventDirs: decision.bookshelfImportFiles,
              );
            });
          }

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
  // Enqueue bookshelf files as UI-only cards (policy B).
  _enqueueBookImportCards(decision.bookshelfFileCards);

  final hasCards = decision.bookshelfFileCards.isNotEmpty;
  final hasAiContent = payload.hasText || payload.hasImages || payload.hasUrls;

  if (!hasAiContent) {
    // No prompt/images to send; still open the AI tab if we have cards.
    if (hasCards) {
      await PapertokAiChatNavigator.show();
    }
    return;
  }

  final ctx = await _waitForNavigatorContext();
  if (ctx == null) {
    AnxLog.warning('share: navigator context not ready; dropping payload');
    return;
  }

  // Convert ShareInboundImage -> File for existing service.
  final imageFiles = payload.images.map((e) => File(e.path)).toList();

  final textFiles = payload.textFiles.map((e) => File(e.path)).toList();
  final docxFiles = payload.docxFiles.map((e) => File(e.path)).toList();

  await ShareToAiService.sendToAiChatFromShare(
    ctx,
    sharedText: payload.sharedText,
    imageFiles: imageFiles,
    textFiles: textFiles,
    docxFiles: docxFiles,
  );

  if (Prefs().sharePanelCleanupAfterUseV1 && !hasCards) {
    // Safe to cleanup only when there are no pending bookshelf cards.
    final allPaths = <String>[
      ...payload.images.map((e) => e.path),
      ...payload.files.map((e) => e.path),
    ];
    Future<void>.delayed(const Duration(seconds: 2), () {
      ShareInboxCleanupService.cleanupEventDirsIfSafe(eventDirs: allPaths);
    });
  }
}

void _enqueueBookImportCards(List<ShareInboundFile> cards) {
  if (cards.isEmpty) return;

  final paths = cards
      .map((e) => e.path.trim())
      .where((p) => p.isNotEmpty)
      .toList(growable: false);

  if (paths.isEmpty) return;

  final existing = pendingShareBookImportPaths.value;
  final seen = <String>{...existing};

  final next = [...existing];
  for (final p in paths) {
    if (seen.add(p)) next.add(p);
  }

  pendingShareBookImportPaths.value = next;
}

Future<void> _showAskThenRoute(
    ShareInboundPayload payload, WidgetRef ref) async {
  final ctx = await _waitForNavigatorContext();
  if (ctx == null) {
    AnxLog.warning('share: navigator context not ready; dropping payload');
    return;
  }

  // Ensure the app is painted before showing the modal (requirement).
  await Future<void>.delayed(const Duration(milliseconds: 16));

  final l10n = L10n.of(ctx);

  final choice = await showDialog<ShareDestination>(
    context: ctx,
    builder: (dialogCtx) {
      return SimpleDialog(
        title: Text(l10n.settingsSharePanelModeTitle),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(ShareDestination.aiChat),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 20),
                const SizedBox(width: 10),
                Text(l10n.settingsSharePanelModeAiChat),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(ShareDestination.bookshelf),
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 20),
                const SizedBox(width: 10),
                Text(l10n.settingsSharePanelModeBookshelf),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Row(
              children: [
                const Icon(Icons.close, size: 20),
                const SizedBox(width: 10),
                Text(l10n.commonCancel),
              ],
            ),
          ),
        ],
      );
    },
  );

  if (choice == null) return;

  switch (choice) {
    case ShareDestination.aiChat:
      final d = ShareInboundDecider.decide(
        mode: SharePanelMode.aiChat,
        payload: payload,
      );
      await _applyDecision(d, payload, ref);
      return;

    case ShareDestination.bookshelf:
      final d = ShareInboundDecider.decide(
        mode: SharePanelMode.bookshelf,
        payload: payload,
      );
      final importFiles = await ShareSafeImport.prepareImportFiles(
        d.bookshelfImportFiles,
      );
      if (importFiles.isEmpty) return;

      importBookList(importFiles, ctx, ref);

      if (Prefs().sharePanelCleanupAfterUseV1) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          ShareInboxCleanupService.cleanupEventDirsIfSafe(
            eventDirs: d.bookshelfImportFiles,
          );
        });
      }

      return;

    case ShareDestination.askUser:
      // Not reachable.
      return;
  }
}

Future<BuildContext?> _waitForNavigatorContext({
  Duration timeout = const Duration(milliseconds: 900),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) return ctx;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  return navigatorKey.currentContext;
}
