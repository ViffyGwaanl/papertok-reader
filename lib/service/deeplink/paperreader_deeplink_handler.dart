import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/book.dart'
    show pushToReadingPage, pushToReadingPageWithContainer;
import 'package:anx_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:anx_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_pending_queue.dart';
import 'package:anx_reader/service/shortcuts/shortcuts_callback_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaperReaderDeepLinkHandler {
  const PaperReaderDeepLinkHandler._();

  static Future<void> handleIncomingUri(WidgetRef ref, Uri uri) async {
    // Shortcuts deep links.
    if (uri.scheme.toLowerCase() == 'paperreader' && uri.host == 'shortcuts') {
      if (uri.path == '/result') {
        ShortcutsCallbackService.instance.handleIncomingUri(uri);
        return;
      }

      // `paperreader://shortcuts/ask` is a best-effort navigation hint.
      // The actual request is delivered via MethodChannel.
      if (uri.path == '/ask') {
        await PapertokAiChatNavigator.show();
        // Best-effort: if a pending ask was queued before UI was ready.
        await PapertokShortcutsPendingQueue.tryDrain();
        return;
      }

      return;
    }

    final intent = PaperReaderReaderIntent.tryParse(uri);
    if (intent == null) return;

    // Defensive bounds.
    final cfi = intent.cfi;
    final href = intent.href;
    if (cfi != null && cfi.length > 20000) {
      AnxLog.warning('deeplink: cfi too long, ignoring');
      return;
    }
    if (href != null && href.length > 20000) {
      AnxLog.warning('deeplink: href too long, ignoring');
      return;
    }

    final books = await const BooksRepository().fetchByIds([intent.bookId]);
    final book = books[intent.bookId];
    if (book == null) {
      AnxLog.warning('deeplink: book not found id=${intent.bookId}');
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      AnxLog.warning('deeplink: navigator context not ready');
      return;
    }

    // Prefer cfi.
    if (cfi != null && cfi.trim().isNotEmpty) {
      await pushToReadingPage(ref, context, book, cfi: cfi);
      return;
    }

    if (href != null && href.trim().isNotEmpty) {
      await pushToReadingPage(ref, context, book, openHref: href);
      return;
    }

    await pushToReadingPage(ref, context, book);
  }

  static Future<void> handleIncomingUriWithContainer(
    ProviderContainer container,
    Uri uri,
  ) async {
    // Shortcuts deep links.
    if (uri.scheme.toLowerCase() == 'paperreader' && uri.host == 'shortcuts') {
      if (uri.path == '/result') {
        ShortcutsCallbackService.instance.handleIncomingUri(uri);
      }
      // In container mode we intentionally do not navigate (needs BuildContext).
      return;
    }

    final intent = PaperReaderReaderIntent.tryParse(uri);
    if (intent == null) return;

    // Defensive bounds.
    final cfi = intent.cfi;
    final href = intent.href;
    if (cfi != null && cfi.length > 20000) {
      AnxLog.warning('deeplink: cfi too long, ignoring');
      return;
    }
    if (href != null && href.length > 20000) {
      AnxLog.warning('deeplink: href too long, ignoring');
      return;
    }

    final books = await const BooksRepository().fetchByIds([intent.bookId]);
    final book = books[intent.bookId];
    if (book == null) {
      AnxLog.warning('deeplink: book not found id=${intent.bookId}');
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      AnxLog.warning('deeplink: navigator context not ready');
      return;
    }

    // Prefer cfi.
    if (cfi != null && cfi.trim().isNotEmpty) {
      await pushToReadingPageWithContainer(container, context, book, cfi: cfi);
      return;
    }

    if (href != null && href.trim().isNotEmpty) {
      await pushToReadingPageWithContainer(
        container,
        context,
        book,
        openHref: href,
      );
      return;
    }

    await pushToReadingPageWithContainer(container, context, book);
  }
}
