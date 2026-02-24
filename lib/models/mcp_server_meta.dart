import 'dart:convert';

import 'package:anx_reader/models/mcp_transport_mode.dart';

class McpServerMeta {
  const McpServerMeta({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.enabled,
    this.transportModeV1 = McpTransportMode.auto,
  });

  final String id;
  final String name;

  /// MCP server URL. In auto mode, this may point to either:
  /// - Streamable HTTP MCP endpoint, e.g. https://example.com/mcp
  /// - Legacy HTTP+SSE SSE endpoint
  final String endpoint;

  final bool enabled;

  final McpTransportMode transportModeV1;

  McpServerMeta copyWith({
    String? id,
    String? name,
    String? endpoint,
    bool? enabled,
    McpTransportMode? transportModeV1,
  }) {
    return McpServerMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      transportModeV1: transportModeV1 ?? this.transportModeV1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'enabled': enabled,
      'transportModeV1': transportModeV1.code,
    };
  }

  static McpServerMeta fromJson(Map<String, dynamic> json) {
    return McpServerMeta(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      enabled: json['enabled'] == true,
      transportModeV1:
          McpTransportMode.fromCode(json['transportModeV1']?.toString()),
    );
  }

  static List<McpServerMeta> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => McpServerMeta.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id.trim().isNotEmpty && e.endpoint.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String encodeList(List<McpServerMeta> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList(growable: false));
  }
}

class McpServerSecret {
  const McpServerSecret({
    this.headers = const {},
  });

  final Map<String, String> headers;

  Map<String, dynamic> toJson() => {
        'headers': headers,
      };

  static McpServerSecret fromJson(Map<String, dynamic> json) {
    final headersRaw = json['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      for (final entry in headersRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value?.toString() ?? '';
        if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
          headers[k] = v;
        }
      }
    }
    return McpServerSecret(headers: headers);
  }
}
