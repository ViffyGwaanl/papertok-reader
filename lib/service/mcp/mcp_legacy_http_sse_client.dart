import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/service/mcp/mcp_http_exception.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

/// Legacy MCP transport: HTTP with SSE (protocol version 2024-11-05).
///
/// Server provides two endpoints:
/// - SSE endpoint (this.clientEndpoint) emits an `endpoint` event telling the
///   client where to POST JSON-RPC messages.
/// - POST endpoint receives JSON-RPC requests/notifications.
///
/// Server messages are sent as SSE `message` events where data is JSON.
import 'package:anx_reader/service/mcp/mcp_rpc_client.dart';

class McpLegacyHttpSseClient implements McpRpcClient {
  McpLegacyHttpSseClient({
    required this.clientEndpoint,
    required this.secret,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Uri clientEndpoint;
  final McpServerSecret secret;

  final http.Client _http;

  StreamSubscription<String>? _sseSub;

  Uri? _postEndpoint;

  int _nextId = 1;

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  @override
  String get transportCode => 'legacy_sse';

  @override
  String? get sessionId => null;

  @override
  String? get negotiatedProtocolVersion => '2024-11-05';

  bool get isConnected => _postEndpoint != null && _sseSub != null;

  @override
  Future<void> close() async {
    try {
      await _sseSub?.cancel();
    } catch (_) {}
    _sseSub = null;

    // Fail all in-flight.
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Legacy SSE closed'));
      }
    }
    _pending.clear();

    _http.close();
  }

  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (isConnected) return;

    final req = http.Request('GET', clientEndpoint);
    req.headers.addAll({
      'Accept': 'text/event-stream',
      ...secret.headers,
    });

    final streamed = await _http.send(req).timeout(timeout);

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw McpHttpException(
        statusCode: streamed.statusCode,
        body: body,
        contentType: (streamed.headers['content-type'] ?? '').toLowerCase(),
        allow: streamed.headers['allow'],
      );
    }

    final contentType = (streamed.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.contains('text/event-stream')) {
      final body = await streamed.stream.bytesToString();
      throw McpHttpException(
        statusCode: streamed.statusCode,
        body: body,
        contentType: contentType,
        allow: streamed.headers['allow'],
      );
    }

    final decoder = const Utf8Decoder(allowMalformed: true);
    final stream = streamed.stream.transform(decoder);

    String? currentEvent;
    final dataLines = <String>[];

    void reset() {
      currentEvent = null;
      dataLines.clear();
    }

    Future<void> flush() async {
      if (dataLines.isEmpty) {
        reset();
        return;
      }
      final data = dataLines.join('\n');
      reset();

      if (currentEvent == 'endpoint') {
        final raw = data.trim();
        if (raw.isNotEmpty) {
          _postEndpoint = clientEndpoint.resolve(raw);
          AnxLog.info('MCP legacy SSE: got post endpoint $_postEndpoint');
        }
        return;
      }

      if (currentEvent == 'message') {
        final raw = data.trim();
        if (raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = decoded.cast<String, dynamic>();
            final id = map['id'];
            if (id is int) {
              final c = _pending.remove(id);
              if (c != null && !c.isCompleted) {
                c.complete(map);
              }
            }
          }
        } catch (e) {
          AnxLog.warning('MCP legacy SSE: failed to decode message: $e');
        }
      }
    }

    Future<void> handleLine(String rawLine) async {
      var line = rawLine;
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) {
        await flush();
        return;
      }
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
        return;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
        return;
      }
      // ignore comments/id/retry
    }

    final ready = Completer<void>();

    var buffer = '';

    _sseSub = stream.listen(
      (chunk) async {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n');
          if (idx < 0) break;
          final line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);
          await handleLine(line);
          if (!ready.isCompleted && _postEndpoint != null) {
            ready.complete();
          }
        }
      },
      onError: (e, st) {
        if (!ready.isCompleted) {
          ready.completeError(e, st);
        }
        // Fail all pending.
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(e, st);
          }
        }
        _pending.clear();
      },
      onDone: () async {
        if (!ready.isCompleted) {
          ready.completeError(StateError('SSE ended before endpoint event'));
        }
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('SSE ended'));
          }
        }
        _pending.clear();
      },
      cancelOnError: true,
    );

    await ready.future.timeout(timeout);
  }

  Future<Map<String, dynamic>> _postRpc(
    Map<String, dynamic> rpc, {
    bool expectNoBody = false,
  }) async {
    final endpoint = _postEndpoint;
    if (endpoint == null) {
      throw StateError('Legacy SSE not connected');
    }

    final req = http.Request('POST', endpoint);
    req.headers.addAll({
      'Content-Type': 'application/json',
      ...secret.headers,
    });
    req.body = jsonEncode(rpc);

    final streamed = await _http.send(req).timeout(const Duration(seconds: 30));

    if (expectNoBody) {
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final body = await streamed.stream.bytesToString();
        throw McpHttpException(
          statusCode: streamed.statusCode,
          body: body,
          contentType: (streamed.headers['content-type'] ?? '').toLowerCase(),
          allow: streamed.headers['allow'],
        );
      }
      return {};
    }

    // For legacy transport, server responses are delivered over SSE message events.
    // Some servers also respond with JSON body; we ignore it.
    await streamed.stream.drain();

    final id = rpc['id'];
    if (id is! int) {
      throw StateError('Legacy request id missing');
    }

    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    return await completer.future.timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> initialize() async {
    await connect();

    final id = _nextId++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {
          'name': 'paper-reader',
          'version': '1.0',
        },
      },
    };

    final res = await _postRpc(payload);
    final result = res['result'];
    if (result is! Map) {
      throw StateError('Invalid initialize response');
    }

    // Send notifications/initialized (no response expected).
    final notify = {
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': {},
    };
    await _postRpc(notify, expectNoBody: true);
  }

  @override
  Future<List<McpToolMeta>> listTools() async {
    final id = _nextId++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/list',
      'params': {},
    };

    final res = await _postRpc(payload);
    final result = res['result'];
    if (result is Map) {
      final toolsRaw = result['tools'];
      if (toolsRaw is List) {
        return toolsRaw
            .whereType<Map>()
            .map((e) => McpToolMeta.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
      }
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> callTool({
    required String name,
    required Map<String, dynamic> arguments,
    int? requestId,
  }) async {
    final id = requestId ?? _nextId++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {
        'name': name,
        'arguments': arguments,
      },
    };

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

  @override
  Future<void> sendCancelled({
    required int requestId,
    String reason = 'User requested cancellation',
  }) async {
    final payload = {
      'jsonrpc': '2.0',
      'method': 'notifications/cancelled',
      'params': {
        'requestId': requestId,
        'reason': reason,
      },
    };

    await _postRpc(payload, expectNoBody: true);
  }
}
