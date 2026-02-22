import 'dart:convert';

class McpToolMeta {
  const McpToolMeta({
    required this.name,
    this.title,
    this.description,
    this.inputSchema,
  });

  final String name;
  final String? title;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (inputSchema != null) 'inputSchema': inputSchema,
    };
  }

  static McpToolMeta fromJson(Map<String, dynamic> json) {
    final schemaRaw = json['inputSchema'];
    return McpToolMeta(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      inputSchema:
          schemaRaw is Map ? schemaRaw.cast<String, dynamic>() : const {},
    );
  }

  static List<McpToolMeta> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => McpToolMeta.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.name.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String encodeList(List<McpToolMeta> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList(growable: false));
  }
}
