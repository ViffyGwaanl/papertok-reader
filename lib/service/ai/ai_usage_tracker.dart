/// Tracks token usage and estimated cost for AI API calls.
///
/// Provides real-time cost visibility so users understand their API spending.
/// Inspired by Claude Code's `cost-tracker.ts`.
class AiUsageTracker {
  int _inputTokens = 0;
  int _outputTokens = 0;
  int _cacheReadTokens = 0;
  int _cacheWriteTokens = 0;
  int _apiCalls = 0;
  int _toolCalls = 0;
  double _estimatedCostUsd = 0.0;

  int get inputTokens => _inputTokens;
  int get outputTokens => _outputTokens;
  int get cacheReadTokens => _cacheReadTokens;
  int get cacheWriteTokens => _cacheWriteTokens;
  int get totalTokens => _inputTokens + _outputTokens;
  int get apiCalls => _apiCalls;
  int get toolCalls => _toolCalls;
  double get estimatedCostUsd => _estimatedCostUsd;

  /// Record usage from a single API call.
  void recordApiCall({
    int inputTokens = 0,
    int outputTokens = 0,
    int cacheReadTokens = 0,
    int cacheWriteTokens = 0,
    AiModelPricing? pricing,
  }) {
    _inputTokens += inputTokens;
    _outputTokens += outputTokens;
    _cacheReadTokens += cacheReadTokens;
    _cacheWriteTokens += cacheWriteTokens;
    _apiCalls++;

    if (pricing != null) {
      _estimatedCostUsd += _calculateCost(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheReadTokens: cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens,
        pricing: pricing,
      );
    }
  }

  /// Record a tool invocation (for analytics).
  void recordToolCall() {
    _toolCalls++;
  }

  /// Reset all counters (e.g. when starting a new conversation).
  void reset() {
    _inputTokens = 0;
    _outputTokens = 0;
    _cacheReadTokens = 0;
    _cacheWriteTokens = 0;
    _apiCalls = 0;
    _toolCalls = 0;
    _estimatedCostUsd = 0.0;
  }

  /// Format a human-readable summary.
  String toSummary() {
    final cost = _estimatedCostUsd > 0
        ? '\$${_estimatedCostUsd.toStringAsFixed(4)}'
        : 'unknown';
    return '$totalTokens tokens ($inputTokens in / $outputTokens out) · '
        '$apiCalls API calls · $toolCalls tools · $cost';
  }

  /// Short format for UI status bar.
  String toShortSummary() {
    if (_estimatedCostUsd > 0) {
      return '${formatTokenCount(totalTokens)} tokens · '
          '\$${_estimatedCostUsd.toStringAsFixed(3)}';
    }
    return '${formatTokenCount(totalTokens)} tokens';
  }

  double _calculateCost({
    required int inputTokens,
    required int outputTokens,
    required int cacheReadTokens,
    required int cacheWriteTokens,
    required AiModelPricing pricing,
  }) {
    final inputCost =
        (inputTokens - cacheReadTokens - cacheWriteTokens) *
            pricing.inputPerMillionTokens /
            1e6;
    final outputCost =
        outputTokens * pricing.outputPerMillionTokens / 1e6;
    final cacheReadCost =
        cacheReadTokens * pricing.cacheReadPerMillionTokens / 1e6;
    final cacheWriteCost =
        cacheWriteTokens * pricing.cacheWritePerMillionTokens / 1e6;
    return inputCost + outputCost + cacheReadCost + cacheWriteCost;
  }

  static String formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

/// Pricing information for a specific model.
class AiModelPricing {
  const AiModelPricing({
    required this.inputPerMillionTokens,
    required this.outputPerMillionTokens,
    this.cacheReadPerMillionTokens = 0,
    this.cacheWritePerMillionTokens = 0,
  });

  /// USD per million input tokens.
  final double inputPerMillionTokens;

  /// USD per million output tokens.
  final double outputPerMillionTokens;

  /// USD per million cached-read tokens.
  final double cacheReadPerMillionTokens;

  /// USD per million cache-write tokens.
  final double cacheWritePerMillionTokens;

  // Common model pricing (as of 2026-04)
  static const sonnet = AiModelPricing(
    inputPerMillionTokens: 3,
    outputPerMillionTokens: 15,
    cacheReadPerMillionTokens: 0.3,
    cacheWritePerMillionTokens: 3.75,
  );

  static const opus = AiModelPricing(
    inputPerMillionTokens: 15,
    outputPerMillionTokens: 75,
    cacheReadPerMillionTokens: 1.5,
    cacheWritePerMillionTokens: 18.75,
  );

  static const gpt4o = AiModelPricing(
    inputPerMillionTokens: 2.5,
    outputPerMillionTokens: 10,
    cacheReadPerMillionTokens: 1.25,
    cacheWritePerMillionTokens: 2.5,
  );

  static const geminiFlash = AiModelPricing(
    inputPerMillionTokens: 0.075,
    outputPerMillionTokens: 0.3,
  );

  static const deepseek = AiModelPricing(
    inputPerMillionTokens: 0.27,
    outputPerMillionTokens: 1.1,
    cacheReadPerMillionTokens: 0.07,
    cacheWritePerMillionTokens: 0.27,
  );
}
