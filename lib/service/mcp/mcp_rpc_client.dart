import 'package:anx_reader/models/mcp_tool_meta.dart';

abstract class McpRpcClient {
  String get transportCode;

  String? get sessionId;

  String? get negotiatedProtocolVersion;

  Future<void> initialize();

  Future<List<McpToolMeta>> listTools();

  Future<Map<String, dynamic>> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  });

  Future<void> close();
}
