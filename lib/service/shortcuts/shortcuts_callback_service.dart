import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/log/common.dart';

/// A tiny in-memory callback router for iOS Shortcuts x-callback-url.
///
/// The Shortcuts app can open:
///   paperreader://shortcuts/result?runId=...&data=...
///   paperreader://shortcuts/success?runId=...
///   paperreader://shortcuts/error?runId=...&message=...
///   paperreader://shortcuts/cancel?runId=...
///
/// This service lets a tool call wait for a matching callback by runId.
class ShortcutsCallbackService {
  ShortcutsCallbackService._();

  static final ShortcutsCallbackService instance = ShortcutsCallbackService._();

  final Map<String, _PendingShortcutsRun> _pending = {};

  /// Best-effort guardrails: keep callback payload small.
  static const int defaultMaxDataChars = 8000;

  void handleIncomingUri(Uri uri) {
    if (uri.scheme != 'paperreader') return;
    if (uri.host != 'shortcuts') return;

    final path = uri.path; // e.g. /result
    final qp = uri.queryParameters;

    final runId = (qp['runId'] ?? '').trim();
    if (runId.isEmpty) {
      AnxLog.log.info('shortcuts: ignore callback without runId: $uri');
      return;
    }

    final status = switch (path) {
      '/result' => 'result',
      '/success' => 'success',
      '/error' => 'error',
      '/cancel' => 'cancel',
      _ => 'unknown',
    };

    final payload = <String, dynamic>{
      'runId': runId,
      'status': status,
      'uri': uri.toString(),
    };

    if (status == 'result') {
      final data = qp['data'];
      final dataB64 = qp['dataB64'];

      String? decoded;
      if (dataB64 != null && dataB64.trim().isNotEmpty) {
        decoded = _tryDecodeBase64Url(dataB64.trim());
        payload['encoding'] = 'base64url';
      } else if (data != null) {
        decoded = data;
        payload['encoding'] = 'url';
      }

      if (decoded != null) {
        final maxChars =
            Prefs().shortcutsCallbackMaxCharsV1.clamp(500, 20000).toInt();
        var truncated = false;
        if (decoded.length > maxChars) {
          decoded = decoded.substring(0, maxChars);
          truncated = true;
        }
        payload['data'] = decoded;
        payload['dataTruncated'] = truncated;
        payload['dataMaxChars'] = maxChars;
      }
    }

    if (status == 'error') {
      final message = qp['message'] ?? qp['error'] ?? '';
      if (message.trim().isNotEmpty) {
        payload['message'] = message;
      }
    }

    final pending = _pending[runId];
    if (pending == null) {
      AnxLog.log.info('shortcuts: callback received but no waiter: $payload');
      return;
    }

    if (status == 'success') {
      // Prefer a /result callback if the shortcut sends one. Otherwise, treat
      // /success as a terminal completion signal (after a short grace period).
      pending.lastSuccessPayload = payload;

      pending.successTimer?.cancel();
      pending.successTimer = Timer(const Duration(milliseconds: 500), () {
        final still = _pending[runId];
        if (still == null) return;
        if (still.completer.isCompleted) {
          _pending.remove(runId);
          return;
        }

        _pending.remove(runId);
        still.completer.complete(payload);
      });
      return;
    }

    // Terminal events: result/error/cancel/unknown.
    pending.successTimer?.cancel();

    _pending.remove(runId);
    if (!pending.completer.isCompleted) {
      pending.completer.complete(payload);
    }
  }

  Future<Map<String, dynamic>> waitForCallback(
    String runId, {
    required Duration timeout,
  }) async {
    final existing = _pending[runId];
    if (existing != null && !existing.completer.isCompleted) {
      throw StateError('Already waiting for shortcuts runId=$runId');
    }

    final pending = _PendingShortcutsRun(runId);
    _pending[runId] = pending;

    try {
      return await pending.completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(runId);
      pending.successTimer?.cancel();
      if (pending.lastSuccessPayload != null) {
        return pending.lastSuccessPayload!;
      }
      return {
        'runId': runId,
        'status': 'timeout',
      };
    }
  }

  String? _tryDecodeBase64Url(String s) {
    try {
      final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
      final padLen = (4 - normalized.length % 4) % 4;
      final padded = normalized + ('=' * padLen);
      final bytes = base64Decode(padded);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }
}

class _PendingShortcutsRun {
  _PendingShortcutsRun(this.runId);

  final String runId;
  final Completer<Map<String, dynamic>> completer =
      Completer<Map<String, dynamic>>();

  /// Stored when we receive /success. We prefer waiting for /result, but if it
  /// never comes we return this as a fallback upon timeout.
  Map<String, dynamic>? lastSuccessPayload;

  Timer? successTimer;
}
