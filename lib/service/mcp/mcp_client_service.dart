import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/service/mcp/mcp_streamable_http_client.dart';
import 'package:anx_reader/utils/log/common.dart';

class McpClientService {
  McpClientService._();

  static final McpClientService instance = McpClientService._();

  final Map<String, McpStreamableHttpClient> _clients = {};
  final Map<String, Future<McpStreamableHttpClient>> _pending = {};

  String _keyFor(McpServerMeta server) {
    return '${server.id}::${server.endpoint.trim()}';
  }

  Future<McpStreamableHttpClient> _ensureClient(McpServerMeta server) async {
    final key = _keyFor(server);
    final existing = _clients[key];
    if (existing != null) return existing;

    final pending = _pending[key];
    if (pending != null) return pending;

    final completer = Completer<McpStreamableHttpClient>();
    _pending[key] = completer.future;

    try {
      final endpoint = Uri.parse(server.endpoint.trim());
      final secret = Prefs().getMcpServerSecret(server.id);

      final client =
          McpStreamableHttpClient(endpoint: endpoint, secret: secret);
      await client.initialize();

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

  Future<List<McpToolMeta>> listTools(McpServerMeta server) async {
    final client = await _ensureClient(server);
    return await client.listTools();
  }

  Future<Map<String, dynamic>> callTool(
    McpServerMeta server, {
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final client = await _ensureClient(server);
    return await client.callTool(name: toolName, arguments: args);
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
