/// Dynamic max_tokens strategy inspired by Claude Code.
///
/// Instead of reserving the full model output capacity (32K-128K tokens)
/// on every request — which wastes API slot capacity — we start with a
/// conservative cap and only escalate if the model actually hits it.
///
/// Based on Claude Code's production data:
/// - p99 output is ~5,000 tokens
/// - 8,000 cap catches >99% of responses
/// - Escalation to 32,000 handles the remaining <1%
class MaxTokensStrategy {
  const MaxTokensStrategy._();

  /// Conservative default cap. Covers >99% of responses.
  static const int defaultCap = 8000;

  /// Escalated cap for responses that hit the default limit.
  static const int escalatedCap = 32000;

  /// Full model capacity fallback.
  static const int fullCap = 64000;

  /// Returns the initial max_tokens to use for a request.
  ///
  /// If [previouslyEscalated] is true (i.e. the last request hit the cap),
  /// returns the escalated value directly.
  static int initial({bool previouslyEscalated = false}) {
    return previouslyEscalated ? escalatedCap : defaultCap;
  }

  /// Returns whether a response indicates the model hit the max_tokens limit.
  ///
  /// When this returns `true`, the caller should retry with [escalatedCap].
  static bool shouldEscalate(String? finishReason, int outputTokens) {
    // "max_tokens" / "length" finish reason means the model wanted to
    // output more but was capped.
    if (finishReason == 'max_tokens' || finishReason == 'length') {
      return true;
    }
    // Also escalate if output is suspiciously close to the cap
    if (outputTokens > defaultCap - 200) {
      return true;
    }
    return false;
  }
}
