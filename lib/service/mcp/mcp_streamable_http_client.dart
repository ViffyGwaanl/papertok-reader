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

    final res = await _postRpc(payload);
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

    if (expectNoBody) {
      if (streamed.statusCode != 202 && streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw StateError(
          'MCP server rejected notification: HTTP ${streamed.statusCode} $body',
        );
      }
      return {};
    }

    final contentType = (streamed.headers['content-type'] ?? '').toLowerCase();

    if (contentType.contains('application/json')) {
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw StateError('Invalid JSON-RPC response');
    }

    if (contentType.contains('text/event-stream')) {
      return await _readSseForResponse(streamed, expectedId: rpc['id']);
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

    final sub = stream.listen(
      (chunk) async {
        // SSE frames are line-based.
        final lines = chunk.split(RegExp(r'\r?\n'));
        for (final line in lines) {
          if (completer.isCompleted) return;
          if (line.isEmpty) {
            await flushEvent(completer);
            continue;
          }
          if (line.startsWith('id:')) {
            eventId = line.substring(3).trim();
            continue;
          }
          if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
            continue;
          }
          // ignore: event:, retry:, comments
        }
      },
      onError: (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      },
      onDone: () async {
        if (!completer.isCompleted) {
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
