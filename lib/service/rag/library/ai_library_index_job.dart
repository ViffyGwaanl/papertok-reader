enum AiLibraryIndexJobStatus {
  queued,
  running,
  paused,
  succeeded,
  failed,
  cancelled,
}

class AiLibraryIndexJob {
  const AiLibraryIndexJob({
    required this.id,
    required this.bookId,
    required this.status,
    required this.retryCount,
    required this.maxRetries,
    required this.progress,
    this.currentChapterHref,
    this.currentChapterTitle,
    this.lastError,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int bookId;
  final AiLibraryIndexJobStatus status;
  final int retryCount;
  final int maxRetries;
  final double progress;
  final String? currentChapterHref;
  final String? currentChapterTitle;
  final String? lastError;
  final int? createdAt;
  final int? updatedAt;

  AiLibraryIndexJob copyWith({
    AiLibraryIndexJobStatus? status,
    int? retryCount,
    int? maxRetries,
    double? progress,
    String? currentChapterHref,
    String? currentChapterTitle,
    String? lastError,
    int? createdAt,
    int? updatedAt,
  }) {
    return AiLibraryIndexJob(
      id: id,
      bookId: bookId,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      progress: progress ?? this.progress,
      currentChapterHref: currentChapterHref ?? this.currentChapterHref,
      currentChapterTitle: currentChapterTitle ?? this.currentChapterTitle,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String statusToDb(AiLibraryIndexJobStatus s) => switch (s) {
        AiLibraryIndexJobStatus.queued => 'queued',
        AiLibraryIndexJobStatus.running => 'running',
        AiLibraryIndexJobStatus.paused => 'paused',
        AiLibraryIndexJobStatus.succeeded => 'succeeded',
        AiLibraryIndexJobStatus.failed => 'failed',
        AiLibraryIndexJobStatus.cancelled => 'cancelled',
      };

  static AiLibraryIndexJobStatus statusFromDb(String raw) => switch (raw) {
        'queued' => AiLibraryIndexJobStatus.queued,
        'running' => AiLibraryIndexJobStatus.running,
        'paused' => AiLibraryIndexJobStatus.paused,
        'succeeded' => AiLibraryIndexJobStatus.succeeded,
        'failed' => AiLibraryIndexJobStatus.failed,
        'cancelled' => AiLibraryIndexJobStatus.cancelled,
        _ => AiLibraryIndexJobStatus.failed,
      };
}
