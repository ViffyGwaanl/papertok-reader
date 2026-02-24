class McpHttpException implements Exception {
  McpHttpException({
    required this.statusCode,
    required this.body,
    this.contentType,
    this.allow,
  });

  final int statusCode;
  final String body;
  final String? contentType;
  final String? allow;

  @override
  String toString() {
    final ct = (contentType ?? '').trim();
    final a = (allow ?? '').trim();
    return 'MCP HTTP $statusCode'
        '${ct.isNotEmpty ? ' content-type=$ct' : ''}'
        '${a.isNotEmpty ? ' allow=$a' : ''}'
        '${body.trim().isNotEmpty ? ' body=$body' : ''}';
  }
}
