/// Global approval policy for AI tool invocations.
///
/// Defaults to [always] for safety.
enum AiToolApprovalPolicy {
  /// Always prompt before invoking any tool.
  always,

  /// Prompt only for write/destructive tools.
  writesOnly,

  /// Never prompt (NOT recommended). High-risk tools may still be forced to
  /// prompt depending on app safety settings.
  never,
  ;

  String get code => name;

  static AiToolApprovalPolicy fromCode(String? code) {
    final v = (code ?? '').trim();
    for (final e in AiToolApprovalPolicy.values) {
      if (e.code == v) return e;
    }
    return AiToolApprovalPolicy.always;
  }
}
