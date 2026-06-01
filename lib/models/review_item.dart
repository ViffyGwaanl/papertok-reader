import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/source_ref.dart';

enum ReviewItemStatus {
  draft('draft'),
  pending('pending'),
  approved('approved'),
  dismissed('dismissed'),
  applied('applied');

  const ReviewItemStatus(this.asString);

  final String asString;

  bool get isTerminal =>
      this == ReviewItemStatus.dismissed || this == ReviewItemStatus.applied;

  bool canTransitionTo(ReviewItemStatus next) {
    return switch (this) {
      ReviewItemStatus.draft => next == ReviewItemStatus.pending,
      ReviewItemStatus.pending =>
        next == ReviewItemStatus.approved || next == ReviewItemStatus.dismissed,
      ReviewItemStatus.approved => next == ReviewItemStatus.applied,
      ReviewItemStatus.dismissed => false,
      ReviewItemStatus.applied => false,
    };
  }

  static ReviewItemStatus fromString(String? value) {
    for (final status in ReviewItemStatus.values) {
      if (status.asString == value) return status;
    }
    return ReviewItemStatus.draft;
  }
}

enum ReviewItemSourceType {
  memoryCandidate('memory-candidate'),
  knowledgeCard('knowledge-card'),
  seminarSynthesis('seminar-synthesis'),
  conceptGraphRelation('concept-graph-relation'),
  flashcardCandidate('flashcard-candidate'),
  imageAnalysisCard('image-analysis-card'),
  reviewHistoryImport('review-history-import'),
  syncConflict('sync-conflict'),
  unknown('unknown');

  const ReviewItemSourceType(this.asString);

  final String asString;

  static ReviewItemSourceType fromString(String? value) {
    for (final type in ReviewItemSourceType.values) {
      if (type.asString == value) return type;
    }
    return ReviewItemSourceType.unknown;
  }
}

@immutable
class ReviewItem {
  factory ReviewItem({
    required String id,
    required ReviewItemSourceType sourceType,
    required String sourceId,
    required String title,
    required String body,
    ReviewItemStatus status = ReviewItemStatus.draft,
    List<SourceRef> sourceRefs = const <SourceRef>[],
    int? createdAt,
    int? updatedAt,
    int? decidedAt,
    int? appliedAt,
    String? decisionSource,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    final normalizedStatus = _normalizeStatus(
      status,
      sourceType,
      sourceRefs,
    );
    return ReviewItem._(
      id: id,
      sourceType: sourceType,
      sourceId: sourceId,
      title: title,
      body: body,
      status: normalizedStatus,
      sourceRefs: sourceRefs,
      createdAt: createdAt,
      updatedAt: updatedAt,
      decidedAt: decidedAt,
      appliedAt:
          normalizedStatus == ReviewItemStatus.applied ? appliedAt : null,
      decisionSource: decisionSource,
      payload: payload,
    );
  }

  const ReviewItem._({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.body,
    required this.status,
    required this.sourceRefs,
    required this.createdAt,
    required this.updatedAt,
    required this.decidedAt,
    required this.appliedAt,
    required this.decisionSource,
    required this.payload,
  });

  final String id;
  final ReviewItemSourceType sourceType;
  final String sourceId;
  final String title;
  final String body;
  final ReviewItemStatus status;
  final List<SourceRef> sourceRefs;
  final int? createdAt;
  final int? updatedAt;
  final int? decidedAt;
  final int? appliedAt;
  final String? decisionSource;
  final Map<String, dynamic> payload;

  bool get hasTraceableSource => sourceRefs.any((ref) => ref.hasEvidence);
  bool get hasReaderBacklink => sourceRefs.any((ref) => ref.hasReaderBacklink);
  bool get hasApplicableSource => switch (sourceType) {
        ReviewItemSourceType.knowledgeCard => hasReaderBacklink,
        _ => hasTraceableSource,
      };
  bool get canApply =>
      status == ReviewItemStatus.approved && hasApplicableSource;

  ReviewItem transitionTo(
    ReviewItemStatus next, {
    required int now,
    String? decisionSource,
  }) {
    if (!status.canTransitionTo(next)) {
      throw StateError(
        'Invalid ReviewItem transition: ${status.asString} -> ${next.asString}',
      );
    }
    if (next == ReviewItemStatus.applied && !hasApplicableSource) {
      throw StateError('ReviewItem cannot be applied without SourceRef.');
    }
    return copyWith(
      status: next,
      updatedAt: now,
      decidedAt: next == ReviewItemStatus.approved ||
              next == ReviewItemStatus.dismissed
          ? now
          : decidedAt,
      appliedAt: next == ReviewItemStatus.applied ? now : appliedAt,
      decisionSource: decisionSource ?? this.decisionSource,
    );
  }

  ReviewItem copyWith({
    String? id,
    ReviewItemSourceType? sourceType,
    String? sourceId,
    String? title,
    String? body,
    ReviewItemStatus? status,
    List<SourceRef>? sourceRefs,
    int? createdAt,
    int? updatedAt,
    int? decidedAt,
    int? appliedAt,
    String? decisionSource,
    Map<String, dynamic>? payload,
  }) {
    return ReviewItem(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      body: body ?? this.body,
      status: status ?? this.status,
      sourceRefs: sourceRefs ?? this.sourceRefs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      decidedAt: decidedAt ?? this.decidedAt,
      appliedAt: appliedAt ?? this.appliedAt,
      decisionSource: decisionSource ?? this.decisionSource,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceType': sourceType.asString,
        'sourceId': sourceId,
        'title': title,
        'body': body,
        'status': status.asString,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (decidedAt != null) 'decidedAt': decidedAt,
        if (appliedAt != null) 'appliedAt': appliedAt,
        if (decisionSource != null) 'decisionSource': decisionSource,
        'payload': payload,
      };

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    final refs = (json['sourceRefs'] as List?)
            ?.whereType<Map>()
            .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false) ??
        const <SourceRef>[];
    final sourceType = ReviewItemSourceType.fromString(
      json['sourceType']?.toString(),
    );
    final status = _normalizeStatus(
      ReviewItemStatus.fromString(json['status']?.toString()),
      sourceType,
      refs,
    );
    return ReviewItem(
      id: (json['id'] ?? '').toString(),
      sourceType: sourceType,
      sourceId: (json['sourceId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      status: status,
      sourceRefs: refs,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
      decidedAt: (json['decidedAt'] as num?)?.toInt(),
      appliedAt: (json['appliedAt'] as num?)?.toInt(),
      decisionSource: json['decisionSource']?.toString(),
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }

  static ReviewItemStatus _normalizeStatus(
    ReviewItemStatus status,
    ReviewItemSourceType sourceType,
    List<SourceRef> sourceRefs,
  ) {
    final hasApplicableSource = switch (sourceType) {
      ReviewItemSourceType.knowledgeCard =>
        sourceRefs.any((ref) => ref.hasReaderBacklink),
      _ => sourceRefs.any((ref) => ref.hasEvidence),
    };
    if (status == ReviewItemStatus.applied && !hasApplicableSource) {
      return ReviewItemStatus.approved;
    }
    return status;
  }
}

@immutable
class SpacedReviewHistoryEntry {
  const SpacedReviewHistoryEntry({
    required this.reviewedAt,
    required this.rating,
    required this.intervalDays,
    this.note,
  });

  final int reviewedAt;
  final String rating;
  final int intervalDays;
  final String? note;

  Map<String, dynamic> toJson() => {
        'reviewedAt': reviewedAt,
        'rating': rating,
        'intervalDays': intervalDays,
        if (note != null) 'note': note,
      };

  factory SpacedReviewHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SpacedReviewHistoryEntry(
      reviewedAt: (json['reviewedAt'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] ?? '').toString(),
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString(),
    );
  }
}

@immutable
class SpacedReviewItem {
  const SpacedReviewItem({
    required this.id,
    required this.cardId,
    required this.prompt,
    required this.answer,
    this.sourceRefs = const <SourceRef>[],
    this.lastReviewedAt,
    this.dueAt,
    this.intervalDays = 0,
    this.lapses = 0,
    this.reviewHistory = const <SpacedReviewHistoryEntry>[],
  });

  final String id;
  final String cardId;
  final String prompt;
  final String answer;
  final List<SourceRef> sourceRefs;
  final int? lastReviewedAt;
  final int? dueAt;
  final int intervalDays;
  final int lapses;
  final List<SpacedReviewHistoryEntry> reviewHistory;

  bool isDue(int now) => dueAt == null || dueAt! <= now;

  SpacedReviewItem recordReview({
    required int reviewedAt,
    required String rating,
    required int nextDueAt,
    required int nextIntervalDays,
    String? note,
  }) {
    final normalizedRating = rating.trim();
    return SpacedReviewItem(
      id: id,
      cardId: cardId,
      prompt: prompt,
      answer: answer,
      sourceRefs: sourceRefs,
      lastReviewedAt: reviewedAt,
      dueAt: nextDueAt,
      intervalDays: nextIntervalDays,
      lapses: normalizedRating == 'again' ? lapses + 1 : lapses,
      reviewHistory: [
        ...reviewHistory,
        SpacedReviewHistoryEntry(
          reviewedAt: reviewedAt,
          rating: normalizedRating,
          intervalDays: nextIntervalDays,
          note: note,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cardId': cardId,
        'prompt': prompt,
        'answer': answer,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        if (lastReviewedAt != null) 'lastReviewedAt': lastReviewedAt,
        if (dueAt != null) 'dueAt': dueAt,
        'intervalDays': intervalDays,
        'lapses': lapses,
        'reviewHistory': reviewHistory
            .map((entry) => entry.toJson())
            .toList(growable: false),
      };

  factory SpacedReviewItem.fromJson(Map<String, dynamic> json) {
    return SpacedReviewItem(
      id: (json['id'] ?? '').toString(),
      cardId: (json['cardId'] ?? '').toString(),
      prompt: (json['prompt'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
      sourceRefs: (json['sourceRefs'] as List?)
              ?.whereType<Map>()
              .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <SourceRef>[],
      lastReviewedAt: (json['lastReviewedAt'] as num?)?.toInt(),
      dueAt: (json['dueAt'] as num?)?.toInt(),
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
      reviewHistory: (json['reviewHistory'] as List?)
              ?.whereType<Map>()
              .map((e) => SpacedReviewHistoryEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <SpacedReviewHistoryEntry>[],
    );
  }
}
