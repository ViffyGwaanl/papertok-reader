enum MemoryWorkflowDailyStrategy {
  smartDaily('smart_daily'),
  reviewInbox('review_inbox'),
  autoDaily('auto_daily');

  const MemoryWorkflowDailyStrategy(this.wire);

  final String wire;

  bool get writesDailyDirectly => this == MemoryWorkflowDailyStrategy.autoDaily;

  bool get routesByConfidence => this == MemoryWorkflowDailyStrategy.smartDaily;

  static MemoryWorkflowDailyStrategy fromWire(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return switch (normalized) {
      'smart_daily' || 'smart' => MemoryWorkflowDailyStrategy.smartDaily,
      'auto_daily' ||
      'daily' ||
      'auto' =>
        MemoryWorkflowDailyStrategy.autoDaily,
      'review_inbox' ||
      'review' ||
      'inbox' =>
        MemoryWorkflowDailyStrategy.reviewInbox,
      _ => MemoryWorkflowDailyStrategy.smartDaily,
    };
  }
}
