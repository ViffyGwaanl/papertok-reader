import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/models/mcp_transport_mode.dart';
import 'package:anx_reader/service/mcp/mcp_connection_test_result.dart';
import 'package:anx_reader/service/mcp/mcp_http_exception.dart';
import 'package:anx_reader/service/mcp/mcp_legacy_http_sse_client.dart';
import 'package:anx_reader/service/mcp/mcp_rpc_client.dart';
import 'package:anx_reader/service/mcp/mcp_streamable_http_client.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

class McpClientService {
  McpClientService._();

  static final McpClientService instance = McpClientService._();

  final Map<String, McpRpcClient> _clients = {};
  final Map<String, Future<McpRpcClient>> _pending = {};

  Future<McpConnectionTestResult> testConnection(
    McpServerMeta server, {
    Duration timeout = const Duration(seconds: 15),
    bool probeGetSse = true,
  }) async {
    try {
      // Force a fresh client to avoid stale sessions.
      await closeServer(server.id);

      final client = await _ensureClient(server).timeout(timeout);
      final tools = await client.listTools().timeout(timeout);

      bool? getSseSupport;
      int? httpStatus;
      String? allow;

      if (probeGetSse) {
        try {
          final secret = Prefs().getMcpServerSecret(server.id);
          final res = await http.get(
            Uri.parse(server.endpoint.trim()),
            headers: {
              'Accept': 'text/event-stream',
              if (client.sessionId?.trim().isNotEmpty == true)
                'MCP-Session-Id': client.sessionId!,
              'MCP-Protocol-Version':
                  client.negotiatedProtocolVersion?.trim().isNotEmpty == true
                      ? client.negotiatedProtocolVersion!
                      : McpStreamableHttpClient.protocolVersion,
              ...secret.headers,
            },
          ).timeout(const Duration(seconds: 6));

          httpStatus = res.statusCode;
          allow = res.headers['allow'];
          if (res.statusCode == 405) {
            getSseSupport = false;
          } else {
            final ct = (res.headers['content-type'] ?? '').toLowerCase();
            getSseSupport = ct.contains('text/event-stream');
          }
        } catch (_) {
          // ignore probe errors
        }
      }

      return McpConnectionTestResult(
        ok: true,
        toolsCount: tools.length,
        protocolVersion: client.negotiatedProtocolVersion,
        sessionId: client.sessionId,
        getSseSupport: getSseSupport,
        httpStatus: httpStatus,
        allowHeader: allow,
      );
    } catch (e) {
      return McpConnectionTestResult(
        ok: false,
        message: e.toString(),
      );
    }
  }

  String _keyFor(McpServerMeta server) {
    return '${server.id}::${server.endpoint.trim()}';
  }

  Future<McpRpcClient> _ensureClient(McpServerMeta server) async {
    final key = _keyFor(server);
    final existing = _clients[key];
    if (existing != null) return existing;

    final pending = _pending[key];
    if (pending != null) return pending;

    final completer = Completer<McpRpcClient>();
    _pending[key] = completer.future;

    try {
      final endpoint = Uri.parse(server.endpoint.trim());
      final secret = Prefs().getMcpServerSecret(server.id);

      Future<McpRpcClient> buildStreamable() async {
        final client =
            McpStreamableHttpClient(endpoint: endpoint, secret: secret);
        await client.initialize();
        return client;
      }

      Future<McpRpcClient> buildLegacy() async {
        final client =
            McpLegacyHttpSseClient(clientEndpoint: endpoint, secret: secret);
        await client.initialize();
        return client;
      }

      final mode = server.transportModeV1;
      McpRpcClient client;

      if (mode == McpTransportMode.streamableHttp) {
        client = await buildStreamable();
      } else if (mode == McpTransportMode.legacyHttpSse) {
        client = await buildLegacy();
      } else {
        // auto: try Streamable HTTP first; if initialize fails with 400/404/405,
        // fallback to legacy HTTP+SSE as per MCP spec.
        try {
          client = await buildStreamable();
        } catch (e) {
          if (e is McpHttpException &&
              (e.statusCode == 400 ||
                  e.statusCode == 404 ||
                  e.statusCode == 405)) {
            client = await buildLegacy();
          } else {
            rethrow;
          }
        }
      }

      _clients[key] = client;
      completer.complete(client);
      return client;
    } catch (e, st) {
      AnxLog.severe(
          'MCP: failed to init client for ${server.endpoint}: $e\n$st');
      completer.completeError(e, st);
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  int _rpcId = 1;

  final Map<int, ({String serverId, McpRpcClient client, int startedAtMs})>
      _inFlight = {};

  Future<void> cancelAllInFlight(
      {String reason = 'User requested cancellation'}) async {
    final items = _inFlight.entries.toList(growable: false);
    _inFlight.clear();

    for (final e in items) {
      try {
        await e.value.client.sendCancelled(requestId: e.key, reason: reason);
      } catch (_) {}
    }
  }

  Future<List<McpToolMeta>> listTools(McpServerMeta server) async {
    final client = await _ensureClient(server);
    return await client
        .listTools()
        .timeout(Duration(seconds: server.listToolsTimeoutSecV1));
  }

  Future<Map<String, dynamic>> callTool(
    McpServerMeta server, {
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final client = await _ensureClient(server);

    final requestId = _rpcId++;
    _inFlight[requestId] = (
      serverId: server.id,
      client: client,
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      return await client
          .callTool(name: toolName, arguments: args, requestId: requestId)
          .timeout(Duration(seconds: server.callToolTimeoutSecV1));
    } on TimeoutException {
      try {
        await client.sendCancelled(
          requestId: requestId,
          reason: 'Client timeout',
        );
      } catch (_) {}
      rethrow;
    } finally {
      _inFlight.remove(requestId);
    }
  }

  Future<void> closeServer(String serverId) async {
    final keys =
        _clients.keys.where((k) => k.startsWith('$serverId::')).toList();
    for (final k in keys) {
      final client = _clients.remove(k);
      try {
        await client?.close();
      } catch (_) {}
    }
  }

  Future<void> cleanup() async {
    final clients = _clients.values.toList(growable: false);
    _clients.clear();
    for (final c in clients) {
      try {
        await c.close();
      } catch (_) {}
    }
  }
}
