class McpSseEndedException implements Exception {
  McpSseEndedException({
    this.lastEventId,
    this.retryMs,
  });

  final String? lastEventId;
  final int? retryMs;

  @override
  String toString() {
    final id = (lastEventId ?? '').trim();
    final retry = retryMs;
    return 'MCP SSE ended before response'
        '${id.isNotEmpty ? ' lastEventId=$id' : ''}'
        '${retry != null ? ' retryMs=$retry' : ''}';
  }
}
