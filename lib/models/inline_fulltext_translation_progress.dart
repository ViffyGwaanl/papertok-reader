class InlineFullTextTranslationProgress {
  const InlineFullTextTranslationProgress({
    required this.active,
    required this.total,
    required this.pending,
    required this.inflight,
    required this.done,
    required this.failed,
    required this.generation,
    required this.updatedAtMs,
  });

  final bool active;
  final int total;
  final int pending;
  final int inflight;
  final int done;
  final int failed;
  final int generation;
  final int updatedAtMs;

  factory InlineFullTextTranslationProgress.idle() {
    return InlineFullTextTranslationProgress(
      active: false,
      total: 0,
      pending: 0,
      inflight: 0,
      done: 0,
      failed: 0,
      generation: 0,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  InlineFullTextTranslationProgress copyWith({
    bool? active,
    int? total,
    int? pending,
    int? inflight,
    int? done,
    int? failed,
    int? generation,
    int? updatedAtMs,
  }) {
    return InlineFullTextTranslationProgress(
      active: active ?? this.active,
      total: total ?? this.total,
      pending: pending ?? this.pending,
      inflight: inflight ?? this.inflight,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      generation: generation ?? this.generation,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
