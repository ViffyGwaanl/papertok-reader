enum McpTransportMode {
  auto,
  streamableHttp,
  legacyHttpSse;

  static McpTransportMode fromCode(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'streamable_http':
      case 'streamableHttp':
        return McpTransportMode.streamableHttp;
      case 'legacy_sse':
      case 'legacyHttpSse':
      case 'http_sse':
      case 'sse':
        return McpTransportMode.legacyHttpSse;
      case 'auto':
      default:
        return McpTransportMode.auto;
    }
  }

  String get code {
    return switch (this) {
      McpTransportMode.auto => 'auto',
      McpTransportMode.streamableHttp => 'streamable_http',
      McpTransportMode.legacyHttpSse => 'legacy_sse',
    };
  }
}
