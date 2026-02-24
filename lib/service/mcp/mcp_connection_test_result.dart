class McpConnectionTestResult {
  const McpConnectionTestResult({
    required this.ok,
    this.toolsCount,
    this.protocolVersion,
    this.sessionId,
    this.getSseSupport,
    this.httpStatus,
    this.allowHeader,
    this.message,
  });

  final bool ok;
  final int? toolsCount;
  final String? protocolVersion;
  final String? sessionId;

  /// null=unknown, true=supported, false=not supported
  final bool? getSseSupport;
  final int? httpStatus;
  final String? allowHeader;
  final String? message;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (toolsCount != null) 'toolsCount': toolsCount,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
        if (sessionId != null) 'sessionId': sessionId,
        if (getSseSupport != null) 'getSseSupport': getSseSupport,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (allowHeader != null) 'allow': allowHeader,
        if (message != null) 'message': message,
      };
}
