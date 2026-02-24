import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/service/mcp/mcp_client_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_core/tools.dart';

class McpToolDescriptor {
  const McpToolDescriptor({
    required this.toolName,
    required this.displayName,
    required this.description,
    required this.serverId,
    required this.serverName,
    required this.rawToolName,
  });

  final String toolName;
  final String displayName;
  final String description;
  final String serverId;
  final String serverName;
  final String rawToolName;
}

class McpToolRegistry {
  /// Tool name prefix.
  ///
  /// Note: OpenAI tool/function names must match `^[a-zA-Z0-9_-]+$`.
  /// We therefore avoid dots in MCP tool names.
  static const String _toolNamePrefix = 'mcp_';

  static final Map<String, McpToolDescriptor> _descriptors = {};

  static McpToolDescriptor? describe(String toolName) => _descriptors[toolName];

  /// Build MCP tools from local cache only.
  ///
  /// Rationale:
  /// - Avoids unexpected background network calls during chat.
  /// - Keeps startup/agent prompt stable.
  ///
  /// Users can refresh the tool list from Settings → AI Tools → MCP Servers.
  static ({List<Tool> tools, List<McpToolDescriptor> descriptors})
      buildCachedTools() {
    try {
      final prefs = Prefs();
      final enabledServers =
          prefs.mcpServersV1.where((s) => s.enabled).toList(growable: false);

      final tools = <Tool>[];
      final descriptors = <McpToolDescriptor>[];

      _descriptors.clear();

      for (final server in enabledServers) {
        final cache = prefs.getMcpToolsCacheV1(server.id);
        if (cache == null || cache.tools.isEmpty) {
          continue;
        }

        for (final meta in cache.tools) {
          final tool = _buildTool(server, meta);
          tools.add(tool);

          final desc = McpToolDescriptor(
            toolName: tool.name,
            displayName: meta.title?.trim().isNotEmpty == true
                ? meta.title!.trim()
                : meta.name,
            description: meta.description?.trim() ?? '',
            serverId: server.id,
            serverName: server.name,
            rawToolName: meta.name,
          );
          descriptors.add(desc);
          _descriptors[tool.name] = desc;
        }
      }

      return (tools: tools, descriptors: descriptors);
    } catch (e) {
      // Prefs may not be initialized yet (e.g. early startup or some tests).
      // MCP tools are optional, so we can safely return an empty set.
      AnxLog.warning('MCP tools unavailable: $e');
      _descriptors.clear();
      return (tools: const <Tool>[], descriptors: const <McpToolDescriptor>[]);
    }
  }

  static Tool _buildTool(McpServerMeta server, McpToolMeta meta) {
    // Keep tool names OpenAI-compatible (see _toolNamePrefix comment) and
    // conservatively fit within common provider limits (64 chars).
    final safeServerKey = _safeNameSegment(server.id, maxLen: 12);
    final remaining = 64 - _toolNamePrefix.length - safeServerKey.length - 1;
    final safeToolKey = _safeNameSegment(
      meta.name,
      maxLen: remaining.clamp(1, 64).toInt(),
    );
    final fullName = '$_toolNamePrefix${safeServerKey}_$safeToolKey';

    final inputSchema = (meta.inputSchema == null || meta.inputSchema!.isEmpty)
        ? const {'type': 'object'}
        : meta.inputSchema!;

    final description = (meta.description?.trim().isNotEmpty == true)
        ? 'External MCP tool from ${server.name}: ${meta.description!.trim()}'
        : 'External MCP tool from ${server.name}: ${meta.name}';

    return Tool.fromFunction<Map<String, dynamic>, String>(
      name: fullName,
      description: description,
      inputJsonSchema: inputSchema,
      func: (input) async {
        try {
          final result = await McpClientService.instance.callTool(
            server,
            toolName: meta.name,
            args: input,
          );

          final sanitized =
              _sanitizeToolResult(result, maxChars: server.maxResultCharsV1);

          return jsonEncode({
            'status': 'ok',
            'name': fullName,
            'server': {
              'id': server.id,
              'name': server.name,
            },
            'tool': meta.name,
            'result': sanitized.value,
            'resultTruncated': sanitized.truncated,
          });
        } catch (e, st) {
          AnxLog.severe('MCP tool call failed: $fullName error=$e\n$st');
          return jsonEncode({
            'status': 'error',
            'name': fullName,
            'message': e.toString(),
          });
        }
      },
      getInputFromJson: (json) => json,
    );
  }

  static ({Map<String, dynamic> value, bool truncated}) _sanitizeToolResult(
    Map<String, dynamic> result, {
    required int maxChars,
  }) {
    var truncated = false;

    dynamic sanitize(dynamic value, int depth) {
      if (depth > 6) {
        truncated = true;
        return '[max depth reached]';
      }

      if (value is String) {
        final maxLen = maxChars.clamp(1000, 50000);
        if (value.length > maxLen) {
          truncated = true;
          return '${value.substring(0, maxLen)}\n…(truncated ${value.length - maxLen} chars)';
        }
        return value;
      }

      if (value is Map) {
        final out = <String, dynamic>{};
        var count = 0;
        for (final entry in value.entries) {
          count++;
          if (count > 60) {
            truncated = true;
            out['__truncated__'] = 'map has more than 60 entries';
            break;
          }
          out[entry.key.toString()] = sanitize(entry.value, depth + 1);
        }
        return out;
      }

      if (value is List) {
        final out = <dynamic>[];
        final limit = value.length > 60 ? 60 : value.length;
        for (var i = 0; i < limit; i++) {
          out.add(sanitize(value[i], depth + 1));
        }
        if (value.length > limit) {
          truncated = true;
          out.add('…(truncated ${value.length - limit} items)');
        }
        return out;
      }

      // Numbers/bools/null/etc.
      return value;
    }

    final sanitized = sanitize(result, 0);
    return (
      value: sanitized is Map<String, dynamic>
          ? sanitized
          : <String, dynamic>{'value': sanitized},
      truncated: truncated,
    );
  }

  static String _safeNameSegment(String raw, {required int maxLen}) {
    // OpenAI-compatible segment: only letters/numbers/underscore/hyphen.
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (cleaned.isEmpty) return 'x';
    if (cleaned.length <= maxLen) return cleaned;

    return cleaned.substring(0, maxLen);
  }
}
