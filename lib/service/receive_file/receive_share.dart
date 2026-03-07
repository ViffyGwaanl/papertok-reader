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

      final sharedText = (media.content ?? '').trim();
      final urls = _extractUrls(sharedText);

      final payload = ShareInboundPayload(
        sharedText: sharedText,
        urls: urls,
        images: images,
        files: files,
      );

      final diagnosticId = ShareInboxDiagnosticsStore.newId();
      final providerTypes = <String>{
        for (final a in attachments)
          if (a != null) a.type.name,
        if (sharedText.isNotEmpty) 'text',
        if (urls.isNotEmpty) 'url',
      }.toList(growable: false)
        ..sort();

      if (!payload.hasText &&
          !payload.hasUrls &&
          !payload.hasImages &&
          payload.files.isEmpty) {
        ShareInboxDiagnosticsStore.append(
          ShareInboundEvent(
            id: diagnosticId,
            atMs: DateTime.now().millisecondsSinceEpoch,
            source: 'share',
            sourceType: 'empty',
            mode: Prefs().sharePanelModeV1,
            destination: 'none',
            textLen: 0,
            images: 0,
            files: 0,
            textFiles: 0,
            docxFiles: 0,
            bookshelfFiles: 0,
            otherFiles: 0,
            urlCount: 0,
            urlHosts: const [],
            titlePresent: false,
            providerTypes: providerTypes,
            eventIds: const [],
            receiveStatus: 'ignored_empty',
            routingStatus: 'skipped',
            handoffStatus: 'skipped',
            cleanupStatus: 'skipped',
            failureReason: '',
          ),
        );
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

      final titlePresent = _titlePresent(payload.sharedText, payload.urls);
      final cleanupEnabled = Prefs().sharePanelCleanupAfterUseV1;

      ShareInboxDiagnosticsStore.append(
        ShareInboundEvent(
          id: diagnosticId,
          atMs: DateTime.now().millisecondsSinceEpoch,
          source: 'share',
          sourceType: _sourceTypeForPayload(payload),
          mode: modeRaw,
          destination: decision.destination.name,
          textLen: payload.sharedText.length,
          images: payload.images.length,
          files: payload.files.length,
          textFiles: payload.textFiles.length,
          docxFiles: payload.docxFiles.length,
          bookshelfFiles: payload.bookshelfFiles.length,
          otherFiles: payload.otherFiles.length,
          urlCount: payload.urls.length,
          urlHosts: _urlHosts(payload.urls),
          titlePresent: titlePresent,
          providerTypes: providerTypes,
          eventIds: eventIds,
          receiveStatus: 'received',
          routingStatus: 'pending',
          handoffStatus: 'pending',
          cleanupStatus: _initialCleanupStatus(
            cleanupEnabled: cleanupEnabled,
            eventIds: eventIds,
          ),
          failureReason: '',
        ),
      );

      switch (decision.destination) {
        case ShareDestination.askUser:
          ShareInboxDiagnosticsStore.updateById(
            diagnosticId,
            (e) => e.copyWith(routingStatus: 'ask'),
          );
          await _showAskThenRoute(
            payload,
            ref,
            diagnosticId: diagnosticId,
            cleanupEnabled: cleanupEnabled,
            eventIds: eventIds,
          );
          return;

        case ShareDestination.bookshelf:
          ShareInboxDiagnosticsStore.updateById(
            diagnosticId,
            (e) => e.copyWith(routingStatus: 'bookshelf'),
          );
          final ctx = await _waitForNavigatorContext();
          if (ctx == null) {
            ShareInboxDiagnosticsStore.updateById(
              diagnosticId,
              (e) => e.copyWith(
                handoffStatus: 'error',
                cleanupStatus: 'skipped',
                failureReason: 'navigator_context_not_ready',
              ),
            );
            AnxLog.warning(
                'share: navigator context not ready; dropping payload');
            return;
          }
          final importFiles = await ShareSafeImport.prepareImportFiles(
            decision.bookshelfImportFiles,
          );

          if (importFiles.isEmpty) {
            ShareInboxDiagnosticsStore.updateById(
              diagnosticId,
              (e) => e.copyWith(
                handoffStatus: 'skipped',
                cleanupStatus: 'skipped',
                failureReason: 'empty_import_files',
              ),
            );
            return;
          }

          importBookList(importFiles, ctx, ref);
          final shouldCleanupNow = cleanupEnabled && eventIds.isNotEmpty;
          ShareInboxDiagnosticsStore.updateById(
            diagnosticId,
            (e) => e.copyWith(
              handoffStatus: 'success',
              cleanupStatus: shouldCleanupNow ? e.cleanupStatus : 'skipped',
            ),
          );

          if (shouldCleanupNow) {
            // Best-effort: cleanup empty event dirs after import (import deletes files).
            Future<void>.delayed(const Duration(seconds: 2), () {
              ShareInboxCleanupService.cleanupEventDirsIfSafe(
                eventDirs: decision.bookshelfImportFiles,
              );
            });
          }

          return;

        case ShareDestination.aiChat:
          ShareInboxDiagnosticsStore.updateById(
            diagnosticId,
            (e) => e.copyWith(routingStatus: 'ai_chat'),
          );
          await _applyDecision(
            decision,
            payload,
            ref,
            diagnosticId: diagnosticId,
            cleanupEnabled: cleanupEnabled,
            eventIds: eventIds,
          );
          return;
      }
    } finally {
      // Always reset; otherwise the plugin may replay the initial media.
      handler.resetInitialSharedMedia();
    }
  }

  handler.sharedMediaStream.listen((SharedMedia media) {
    handleShare(media);
  }, onError: (err, st) {
    ShareInboxDiagnosticsStore.append(
      ShareInboundEvent(
        id: ShareInboxDiagnosticsStore.newId(),
        atMs: DateTime.now().millisecondsSinceEpoch,
        source: 'share',
        sourceType: 'stream_error',
        mode: Prefs().sharePanelModeV1,
        destination: 'unknown',
        textLen: 0,
        images: 0,
        files: 0,
        textFiles: 0,
        docxFiles: 0,
        bookshelfFiles: 0,
        otherFiles: 0,
        urlCount: 0,
        urlHosts: const [],
        titlePresent: false,
        providerTypes: const [],
        eventIds: const [],
        receiveStatus: 'error',
        routingStatus: 'error',
        handoffStatus: 'error',
        cleanupStatus: 'skipped',
        failureReason: err.toString(),
      ),
    );
    AnxLog.severe('share: Receive share intent stream error: $err', err, st);
  });

  handler.getInitialSharedMedia().then((media) {
    handleShare(media);
  }, onError: (err, st) {
    ShareInboxDiagnosticsStore.append(
      ShareInboundEvent(
        id: ShareInboxDiagnosticsStore.newId(),
        atMs: DateTime.now().millisecondsSinceEpoch,
        source: 'share',
        sourceType: 'initial_error',
        mode: Prefs().sharePanelModeV1,
        destination: 'unknown',
        textLen: 0,
        images: 0,
        files: 0,
        textFiles: 0,
        docxFiles: 0,
        bookshelfFiles: 0,
        otherFiles: 0,
        urlCount: 0,
        urlHosts: const [],
        titlePresent: false,
        providerTypes: const [],
        eventIds: const [],
        receiveStatus: 'error',
        routingStatus: 'error',
        handoffStatus: 'error',
        cleanupStatus: 'skipped',
        failureReason: err.toString(),
      ),
    );
    AnxLog.severe('share: Receive share intent initial error: $err', err, st);
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
  WidgetRef ref, {
  required String diagnosticId,
  required bool cleanupEnabled,
  required List<String> eventIds,
}) async {
  // Enqueue bookshelf files as UI-only cards (policy B).
  _enqueueBookImportCards(decision.bookshelfFileCards);

  final hasCards = decision.bookshelfFileCards.isNotEmpty;
  final hasAiContent = payload.hasText ||
      payload.hasImages ||
      payload.hasUrls ||
      payload.textFiles.isNotEmpty ||
      payload.docxFiles.isNotEmpty;

  if (!hasAiContent) {
    // No prompt/images to send; still open the AI tab if we have cards.
    if (hasCards) {
      await PapertokAiChatNavigator.show();
      ShareInboxDiagnosticsStore.updateById(
        diagnosticId,
        (e) => e.copyWith(
          handoffStatus: 'cards_only',
          cleanupStatus: 'skipped',
        ),
      );
    } else {
      ShareInboxDiagnosticsStore.updateById(
        diagnosticId,
        (e) => e.copyWith(
          handoffStatus: 'skipped',
          cleanupStatus: 'skipped',
        ),
      );
    }
    return;
  }

  final ctx = await _waitForNavigatorContext();
  if (ctx == null) {
    ShareInboxDiagnosticsStore.updateById(
      diagnosticId,
      (e) => e.copyWith(
        handoffStatus: 'error',
        cleanupStatus: 'skipped',
        failureReason: 'navigator_context_not_ready',
      ),
    );
    AnxLog.warning('share: navigator context not ready; dropping payload');
    return;
  }

  // Convert ShareInboundImage -> File for existing service.
  final imageFiles = payload.images.map((e) => File(e.path)).toList();

  final textFiles = payload.textFiles.map((e) => File(e.path)).toList();
  final docxFiles = payload.docxFiles.map((e) => File(e.path)).toList();

  final sendStatus = await ShareToAiService.sendToAiChatFromShare(
    ctx,
    sharedText: payload.sharedText,
    imageFiles: imageFiles,
    textFiles: textFiles,
    docxFiles: docxFiles,
  );

  final shouldCleanupNow = cleanupEnabled &&
      eventIds.isNotEmpty &&
      !hasCards &&
      sendStatus == ShareToAiSendStatus.success;

  ShareInboxDiagnosticsStore.updateById(
    diagnosticId,
    (e) => e.copyWith(
      handoffStatus: switch (sendStatus) {
        ShareToAiSendStatus.success => 'success',
        ShareToAiSendStatus.skipped => 'skipped',
        ShareToAiSendStatus.failed => 'error',
      },
      cleanupStatus: shouldCleanupNow ? e.cleanupStatus : 'skipped',
      failureReason: sendStatus == ShareToAiSendStatus.failed
          ? 'share_to_ai_failed'
          : e.failureReason,
    ),
  );

  if (shouldCleanupNow) {
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
  ShareInboundPayload payload,
  WidgetRef ref, {
  required String diagnosticId,
  required bool cleanupEnabled,
  required List<String> eventIds,
}) async {
  final ctx = await _waitForNavigatorContext();
  if (ctx == null) {
    ShareInboxDiagnosticsStore.updateById(
      diagnosticId,
      (e) => e.copyWith(
        handoffStatus: 'error',
        cleanupStatus: 'skipped',
        failureReason: 'navigator_context_not_ready',
      ),
    );
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

  if (choice == null) {
    ShareInboxDiagnosticsStore.updateById(
      diagnosticId,
      (e) => e.copyWith(
        routingStatus: 'cancelled',
        handoffStatus: 'cancelled',
        cleanupStatus: 'skipped',
      ),
    );
    return;
  }

  switch (choice) {
    case ShareDestination.aiChat:
      ShareInboxDiagnosticsStore.updateById(
        diagnosticId,
        (e) => e.copyWith(routingStatus: 'ai_chat'),
      );
      final d = ShareInboundDecider.decide(
        mode: SharePanelMode.aiChat,
        payload: payload,
      );
      await _applyDecision(
        d,
        payload,
        ref,
        diagnosticId: diagnosticId,
        cleanupEnabled: cleanupEnabled,
        eventIds: eventIds,
      );
      return;

    case ShareDestination.bookshelf:
      ShareInboxDiagnosticsStore.updateById(
        diagnosticId,
        (e) => e.copyWith(routingStatus: 'bookshelf'),
      );
      final d = ShareInboundDecider.decide(
        mode: SharePanelMode.bookshelf,
        payload: payload,
      );
      final importFiles = await ShareSafeImport.prepareImportFiles(
        d.bookshelfImportFiles,
      );
      if (importFiles.isEmpty) {
        ShareInboxDiagnosticsStore.updateById(
          diagnosticId,
          (e) => e.copyWith(
            handoffStatus: 'skipped',
            cleanupStatus: 'skipped',
            failureReason: 'empty_import_files',
          ),
        );
        return;
      }

      importBookList(importFiles, ctx, ref);
      final shouldCleanupNow = cleanupEnabled && eventIds.isNotEmpty;
      ShareInboxDiagnosticsStore.updateById(
        diagnosticId,
        (e) => e.copyWith(
          handoffStatus: 'success',
          cleanupStatus: shouldCleanupNow ? e.cleanupStatus : 'skipped',
        ),
      );

      if (shouldCleanupNow) {
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

List<Uri> _extractUrls(String text) {
  final out = <Uri>[];
  final matches = RegExp(r'https?://\S+', caseSensitive: false)
      .allMatches(text)
      .map((m) => m.group(0) ?? '');
  for (final raw in matches) {
    final cleaned = raw.replaceAll(RegExp(r'[),.;]+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null) continue;
    if (!uri.hasScheme || uri.host.trim().isEmpty) continue;
    if (!out.any((e) => e.toString() == uri.toString())) {
      out.add(uri);
    }
  }
  return out;
}

bool _titlePresent(String text, List<Uri> urls) {
  var remaining = text;
  for (final url in urls) {
    remaining = remaining.replaceAll(url.toString(), ' ');
  }
  final lines = remaining
      .split(RegExp(r'\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  return lines.isNotEmpty;
}

String _sourceTypeForPayload(ShareInboundPayload payload) {
  final titleOnlyText = !_titlePresent(payload.sharedText, payload.urls);
  if (payload.urls.isNotEmpty &&
      !payload.hasImages &&
      payload.files.isEmpty &&
      titleOnlyText) {
    return 'web_url_only';
  }
  if (payload.urls.isNotEmpty) return 'web_or_link';
  if (payload.docxFiles.isNotEmpty) return 'docx';
  if (payload.textFiles.isNotEmpty) return 'text';
  if (payload.bookshelfFiles.isNotEmpty && !payload.hasAiContent) {
    return 'bookshelf';
  }
  if (payload.images.isNotEmpty && payload.files.isEmpty) return 'images';
  if (payload.files.isNotEmpty) return 'files';
  if (payload.hasText) return 'text_only';
  return 'unknown';
}

String _initialCleanupStatus({
  required bool cleanupEnabled,
  required List<String> eventIds,
}) {
  if (!cleanupEnabled || eventIds.isEmpty) {
    return 'skipped';
  }
  return 'pending';
}

List<String> _urlHosts(List<Uri> urls) {
  final hosts = <String>{};
  for (final url in urls) {
    final host = url.host.trim().toLowerCase();
    if (host.isNotEmpty) hosts.add(host);
  }
  return hosts.toList(growable: false)..sort();
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
