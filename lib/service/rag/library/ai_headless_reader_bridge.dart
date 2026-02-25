import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class AiHeadlessReaderBridge {
  AiHeadlessReaderBridge({
    required this.book,
  });

  final Book book;

  AnxHeadlessWebView? _webView;
  InAppWebViewController? _controller;
  Completer<void>? _readyCompleter;
  Completer<List<TocItem>>? _tocCompleter;

  bool get isActive => _webView != null && _controller != null;

  Future<void> ensureInitialized() async {
    if (isActive) return;

    final url = _buildBookUrl();

    final loadCompleter = Completer<void>();
    _readyCompleter = Completer<void>();
    _tocCompleter = Completer<List<TocItem>>();

    final headless = AnxHeadlessWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        supportZoom: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onLoadEnd',
          callback: (args) {
            final ready = _readyCompleter;
            if (ready != null && !ready.isCompleted) {
              ready.complete();
            }
            return null;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onSetToc',
          callback: (args) {
            try {
              if (args.isEmpty) return null;
              final payload = args.first;
              if (payload is List) {
                final toc = payload
                    .whereType<Map>()
                    .map((e) => TocItem.fromJson(Map<String, dynamic>.from(e)))
                    .toList();
                final c = _tocCompleter;
                if (c != null && !c.isCompleted) {
                  c.complete(toc);
                }
              }
            } catch (e) {
              AnxLog.warning('AiHeadlessReaderBridge: toc parse failed: $e');
            }
            return null;
          },
        );
      },
      onLoadStop: (controller, url) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.complete();
        }
      },
      onConsoleMessage: webviewConsoleMessage,
      onLoadError: (controller, url, code, message) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception('Failed to load reader: [$code] $message'),
          );
        }
      },
      onLoadHttpError: (controller, url, statusCode, description) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception(
              'HTTP error while loading reader: [$statusCode] $description',
            ),
          );
        }
      },
    );

    _webView = headless;
    await headless.run();

    await loadCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'Timed out loading headless reader for book ${book.id}',
      ),
    );

    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for headless reader ready for book ${book.id}',
        ),
      );
    }
  }

  Future<List<TocItem>> getToc(
      {Duration timeout = const Duration(seconds: 10)}) async {
    await ensureInitialized();
    final c = _tocCompleter;
    if (c == null) return const <TocItem>[];
    try {
      return await c.future.timeout(timeout);
    } catch (_) {
      return const <TocItem>[];
    }
  }

  Future<String> getChapterContentByHref(
    String href, {
    int? maxCharacters,
  }) async {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return '';

    await ensureInitialized();
    final controller = _controller;
    if (controller == null) {
      throw StateError('Headless reader controller is not available.');
    }

    final result = await controller.callAsyncJavaScript(
      functionBody:
          'return await getChapterContentByHref("${trimmed.replaceAll('"', '\\"')}")',
    );

    final value = result?.value;
    if (value is String) {
      final text = value.trim();
      if (maxCharacters != null &&
          maxCharacters > 0 &&
          text.length > maxCharacters) {
        return text.substring(0, maxCharacters);
      }
      return text;
    }
    return '';
  }

  String _buildBookUrl() {
    final encodedPath = Uri.encodeComponent(book.fileFullPath);
    final url = 'http://127.0.0.1:${Server().port}/book/$encodedPath';
    final initialCfi = book.lastReadPosition;
    return generateUrl(
      url,
      initialCfi,
      importing: false,
    );
  }

  Future<void> dispose() async {
    try {
      await _webView?.dispose();
    } catch (e) {
      AnxLog.warning('AiHeadlessReaderBridge: dispose failed: $e');
    }
    _webView = null;
    _controller = null;
    _readyCompleter = null;
    _tocCompleter = null;
  }
}
