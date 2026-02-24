import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

class McpStreamableHttpClient {
  McpStreamableHttpClient({
    required this.endpoint,
    required this.secret,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const String protocolVersion = '2025-11-25';

  final Uri endpoint;
  final McpServerSecret secret;

  final http.Client _http;

  String? _sessionId;
  String? _negotiatedProtocolVersion;

  String? get sessionId => _sessionId;

  String? get negotiatedProtocolVersion => _negotiatedProtocolVersion;

  Future<void> close() async {
    _http.close();
  }

  Map<String, String> _baseHeaders({
    required bool includeAcceptJson,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'MCP-Protocol-Version':
          _negotiatedProtocolVersion?.trim().isNotEmpty == true
              ? _negotiatedProtocolVersion!
              : protocolVersion,
    };

    if (includeAcceptJson) {
      headers['Accept'] = 'application/json, text/event-stream';
    } else {
      headers['Accept'] = 'text/event-stream';
    }

    final sid = _sessionId;
    if (sid != null && sid.trim().isNotEmpty) {
      headers['MCP-Session-Id'] = sid;
    }

    headers.addAll(secret.headers);
    return headers;
  }

  int _nextId = 1;

  Map<String, dynamic> _rpc({
    required String method,
    Map<String, dynamic>? params,
    int? id,
  }) {
    final obj = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
    };
    if (id != null) {
      obj['id'] = id;
    }
    if (params != null) {
      obj['params'] = params;
    }
    return obj;
  }

  Future<void> initialize({
    String clientName = 'Paper Reader',
    String clientVersion = '1.0.0',
    bool allowSessionRetry = false,
  }) async {
    final requestId = _nextId++;

    final payload = _rpc(
      method: 'initialize',
      id: requestId,
      params: {
        'protocolVersion': protocolVersion,
        'capabilities': {
          // Phase 1: we only need tools.
        },
        'clientInfo': {
          'name': clientName,
          'version': clientVersion,
        },
      },
    );

    final res = await _postRpc(payload, allowSessionRetry: allowSessionRetry);
    final result = res['result'];
    if (result is Map) {
      final pv = result['protocolVersion']?.toString();
      if (pv != null && pv.trim().isNotEmpty) {
        _negotiatedProtocolVersion = pv;
      }
    }

    // Send initialized notification.
    await _postRpc(
      _rpc(method: 'notifications/initialized'),
      expectNoBody: true,
      allowSessionRetry: allowSessionRetry,
    );
  }

  Future<List<McpToolMeta>> listTools() async {
    String? cursor;
    final tools = <McpToolMeta>[];

    while (true) {
      final requestId = _nextId++;
      final payload = _rpc(
        method: 'tools/list',
        id: requestId,
        params: {
          if (cursor != null) 'cursor': cursor,
        },
      );

      final res = await _postRpc(payload);
      final result = res['result'];
      if (result is! Map) break;

      final listRaw = result['tools'];
      if (listRaw is List) {
        for (final item in listRaw) {
          if (item is Map) {
            final meta = McpToolMeta.fromJson(item.cast<String, dynamic>());
            if (meta.name.trim().isNotEmpty) {
              tools.add(meta);
            }
          }
        }
      }

      final next = result['nextCursor']?.toString();
      if (next == null || next.trim().isEmpty) {
        break;
      }
      cursor = next;
    }

    return tools;
  }

  Future<Map<String, dynamic>> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final requestId = _nextId++;
    final payload = _rpc(
      method: 'tools/call',
      id: requestId,
      params: {
        'name': name,
        'arguments': arguments,
      },
    );

    final res = await _postRpc(payload);
    final result = res['result'];
    if (result is Map) {
      return result.cast<String, dynamic>();
    }
    return {
      'isError': true,
      'content': [
        {
          'type': 'text',
          'text': 'Invalid tools/call result',
        }
      ],
    };
  }

  Future<Map<String, dynamic>> _postRpc(
    Map<String, dynamic> rpc, {
    bool expectNoBody = false,
    bool allowSessionRetry = true,
  }) async {
    final req = http.Request('POST', endpoint);
    req.headers.addAll(_baseHeaders(includeAcceptJson: true));
    req.body = jsonEncode(rpc);

    final streamed = await _http.send(req).timeout(const Duration(seconds: 30));

    // Capture session id if present.
    final sid = streamed.headers['mcp-session-id'] ??
        streamed.headers['MCP-Session-Id'] ??
        streamed.headers['Mcp-Session-Id'];
    if (sid != null && sid.trim().isNotEmpty) {
      _sessionId = sid;
    }

    final status = streamed.statusCode;
    final contentType = (streamed.headers['content-type'] ?? '').toLowerCase();

    bool isSessionInvalidHttp(int code) {
      return code == 404 || code == 410;
    }

    bool isRetryableForSession() {
      final method = rpc['method']?.toString() ?? '';
      return method != 'initialize' && method != 'notifications/initialized';
    }

    if (expectNoBody) {
      if (status < 200 || status >= 300) {
        final body = await streamed.stream.bytesToString();
        throw StateError(
          'MCP server rejected notification: HTTP $status content-type=$contentType body=$body',
        );
      }
      return {};
    }

    if (status < 200 || status >= 300) {
      final body = await streamed.stream.bytesToString();
      if (allowSessionRetry &&
          _sessionId != null &&
          isSessionInvalidHttp(status) &&
          isRetryableForSession()) {
        AnxLog.warning(
          'MCP HTTP $status indicates session invalid; reinitializing and retrying rpc method=${rpc['method']}',
        );
        _sessionId = null;
        _negotiatedProtocolVersion = null;
        await initialize(allowSessionRetry: false);
        return await _postRpc(
          rpc,
          expectNoBody: expectNoBody,
          allowSessionRetry: false,
        );
      }

      throw StateError(
        'MCP server error: HTTP $status content-type=$contentType body=$body',
      );
    }

    if (contentType.contains('application/json')) {
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final map = decoded.cast<String, dynamic>();

        final error = map['error'];
        if (error != null) {
          final errorStr = error.toString().toLowerCase();
          final looksLikeSessionInvalid = errorStr.contains('session') &&
              (errorStr.contains('invalid') ||
                  errorStr.contains('not found') ||
                  errorStr.contains('expired'));

          if (allowSessionRetry &&
              _sessionId != null &&
              looksLikeSessionInvalid &&
              isRetryableForSession()) {
            AnxLog.warning(
              'MCP JSON-RPC error indicates session invalid; reinitializing and retrying rpc method=${rpc['method']}',
            );
            _sessionId = null;
            _negotiatedProtocolVersion = null;
            await initialize(allowSessionRetry: false);
            return await _postRpc(
              rpc,
              expectNoBody: expectNoBody,
              allowSessionRetry: false,
            );
          }

          throw StateError('MCP JSON-RPC error: $error');
        }

        return map;
      }
      throw StateError('Invalid JSON-RPC response');
    }

    if (contentType.contains('text/event-stream')) {
      final map = await _readSseForResponse(streamed, expectedId: rpc['id']);
      final error = map['error'];
      if (error != null) {
        final errorStr = error.toString().toLowerCase();
        final looksLikeSessionInvalid = errorStr.contains('session') &&
            (errorStr.contains('invalid') ||
                errorStr.contains('not found') ||
                errorStr.contains('expired'));

        if (allowSessionRetry &&
            _sessionId != null &&
            looksLikeSessionInvalid &&
            isRetryableForSession()) {
          AnxLog.warning(
            'MCP SSE JSON-RPC error indicates session invalid; reinitializing and retrying rpc method=${rpc['method']}',
          );
          _sessionId = null;
          _negotiatedProtocolVersion = null;
          await initialize(allowSessionRetry: false);
          return await _postRpc(
            rpc,
            expectNoBody: expectNoBody,
            allowSessionRetry: false,
          );
        }

        throw StateError('MCP JSON-RPC error: $error');
      }
      return map;
    }

    final body = await streamed.stream.bytesToString();
    throw StateError(
      'Unexpected MCP response: HTTP ${streamed.statusCode} content-type=$contentType body=$body',
    );
  }

  Future<Map<String, dynamic>> _readSseForResponse(
    http.StreamedResponse response, {
    required Object? expectedId,
  }) async {
    final decoder = const Utf8Decoder(allowMalformed: true);
    final stream = response.stream.transform(decoder);

    String? eventId;
    final dataLines = <String>[];

    Future<void> flushEvent(Completer<Map<String, dynamic>> completer) async {
      if (dataLines.isEmpty) {
        eventId = null;
        return;
      }

      final data = dataLines.join('\n');
      dataLines.clear();

      // Some servers send an empty priming event.
      if (data.trim().isEmpty) {
        eventId = null;
        return;
      }

      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          if (expectedId != null && map['id'] == expectedId) {
            completer.complete(map);
          }
        }
      } catch (e) {
        AnxLog.warning('MCP SSE: failed to decode event data: $e');
      }

      eventId = null;
    }

    final completer = Completer<Map<String, dynamic>>();

    var buffer = '';

    Future<void> handleLine(String rawLine) async {
      if (completer.isCompleted) return;

      var line = rawLine;
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }

      if (line.isEmpty) {
        await flushEvent(completer);
        return;
      }
      if (line.startsWith('id:')) {
        eventId = line.substring(3).trim();
        return;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
        return;
      }
      // ignore: event:, retry:, comments
    }

    final sub = stream.listen(
      (chunk) async {
        buffer += chunk;

        while (true) {
          final idx = buffer.indexOf('\n');
          if (idx < 0) break;

          final line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);

          await handleLine(line);
          if (completer.isCompleted) return;
        }
      },
      onError: (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      },
      onDone: () async {
        if (!completer.isCompleted) {
          if (buffer.isNotEmpty) {
            await handleLine(buffer);
            buffer = '';
          }

          // One last flush.
          await flushEvent(completer);
        }
        if (!completer.isCompleted) {
          completer.completeError(StateError('SSE ended before response'));
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await sub.cancel();
    }
  }
}
