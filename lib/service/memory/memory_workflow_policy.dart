enum MemoryWorkflowDailyStrategy {
  reviewInbox('review_inbox'),
  autoDaily('auto_daily');

  const MemoryWorkflowDailyStrategy(this.wire);

  final String wire;

  bool get writesDailyDirectly => this == MemoryWorkflowDailyStrategy.autoDaily;

  static MemoryWorkflowDailyStrategy fromWire(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return switch (normalized) {
      'auto_daily' ||
      'daily' ||
      'auto' =>
        MemoryWorkflowDailyStrategy.autoDaily,
      _ => MemoryWorkflowDailyStrategy.reviewInbox,
    };
  }
}
