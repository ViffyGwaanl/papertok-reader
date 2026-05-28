import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/source_ref.dart';

enum KnowledgeCardOrigin {
  selection('selection'),
  note('note'),
  aiChat('ai-chat'),
  seminar('seminar'),
  imageAnalysis('image-analysis'),
  ragEvidence('rag-evidence'),
  memoryCandidate('memory-candidate'),
  manual('manual'),
  unknown('unknown');

  const KnowledgeCardOrigin(this.asString);

  final String asString;

  static KnowledgeCardOrigin fromString(String? value) {
    for (final origin in KnowledgeCardOrigin.values) {
      if (origin.asString == value) return origin;
    }
    return KnowledgeCardOrigin.unknown;
  }
}

enum KnowledgeCardReviewState {
  draft('draft'),
  pending('pending'),
  approved('approved'),
  dismissed('dismissed'),
  applied('applied');

  const KnowledgeCardReviewState(this.asString);

  final String asString;

  bool get isTerminal =>
      this == KnowledgeCardReviewState.dismissed ||
      this == KnowledgeCardReviewState.applied;

  static KnowledgeCardReviewState fromString(String? value) {
    for (final state in KnowledgeCardReviewState.values) {
      if (state.asString == value) return state;
    }
    return KnowledgeCardReviewState.draft;
  }
}

@immutable
class KnowledgeCard {
  factory KnowledgeCard({
    required String id,
    required String title,
    required String quote,
    required String explanation,
    String? userNote,
    List<SourceRef> sourceRefs = const <SourceRef>[],
    List<String> conceptRefs = const <String>[],
    List<String> tags = const <String>[],
    KnowledgeCardReviewState reviewState = KnowledgeCardReviewState.draft,
    KnowledgeCardOrigin origin = KnowledgeCardOrigin.unknown,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    int? createdAt,
    int? updatedAt,
  }) {
    final normalizedReviewState = _normalizeReviewState(
      reviewState: reviewState,
      sourceRefs: sourceRefs,
      ownership: ownership,
    );
    return KnowledgeCard._(
      id: id,
      title: title,
      quote: quote,
      explanation: explanation,
      userNote: userNote,
      sourceRefs: sourceRefs,
      conceptRefs: conceptRefs,
      tags: tags,
      reviewState: normalizedReviewState,
      origin: origin,
      ownership: ownership,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  const KnowledgeCard._({
    required this.id,
    required this.title,
    required this.quote,
    required this.explanation,
    required this.userNote,
    required this.sourceRefs,
    required this.conceptRefs,
    required this.tags,
    required this.reviewState,
    required this.origin,
    required this.ownership,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String quote;
  final String explanation;
  final String? userNote;
  final List<SourceRef> sourceRefs;
  final List<String> conceptRefs;
  final List<String> tags;
  final KnowledgeCardReviewState reviewState;
  final KnowledgeCardOrigin origin;
  final AiOutputOwnership ownership;
  final int? createdAt;
  final int? updatedAt;

  bool get hasTraceableSource => sourceRefs.any((ref) => ref.hasEvidence);

  bool get canApply =>
      reviewState == KnowledgeCardReviewState.approved && hasTraceableSource;

  bool get isUserAsset =>
      reviewState == KnowledgeCardReviewState.applied &&
      ownership != AiOutputOwnership.aiGeneratedDraft &&
      hasTraceableSource;

  KnowledgeCard copyWith({
    String? id,
    String? title,
    String? quote,
    String? explanation,
    String? userNote,
    List<SourceRef>? sourceRefs,
    List<String>? conceptRefs,
    List<String>? tags,
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
    AiOutputOwnership? ownership,
    int? createdAt,
    int? updatedAt,
  }) {
    return KnowledgeCard(
      id: id ?? this.id,
      title: title ?? this.title,
      quote: quote ?? this.quote,
      explanation: explanation ?? this.explanation,
      userNote: userNote ?? this.userNote,
      sourceRefs: sourceRefs ?? this.sourceRefs,
      conceptRefs: conceptRefs ?? this.conceptRefs,
      tags: tags ?? this.tags,
      reviewState: reviewState ?? this.reviewState,
      origin: origin ?? this.origin,
      ownership: ownership ?? this.ownership,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'quote': quote,
        'explanation': explanation,
        if (userNote != null) 'userNote': userNote,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        'conceptRefs': conceptRefs,
        'tags': tags,
        'reviewState': reviewState.asString,
        'origin': origin.asString,
        'ownership': ownership.asString,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory KnowledgeCard.fromJson(Map<String, dynamic> json) {
    return KnowledgeCard(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      quote: (json['quote'] ?? '').toString(),
      explanation: (json['explanation'] ?? '').toString(),
      userNote: json['userNote']?.toString(),
      sourceRefs: (json['sourceRefs'] as List?)
              ?.whereType<Map>()
              .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <SourceRef>[],
      conceptRefs: _stringList(json['conceptRefs']),
      tags: _stringList(json['tags']),
      reviewState:
          KnowledgeCardReviewState.fromString(json['reviewState']?.toString()),
      origin: KnowledgeCardOrigin.fromString(json['origin']?.toString()),
      ownership: AiOutputOwnership.fromString(json['ownership']?.toString()),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );
  }

  static List<String> _stringList(Object? value) {
    return (value as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
  }

  static KnowledgeCardReviewState _normalizeReviewState({
    required KnowledgeCardReviewState reviewState,
    required List<SourceRef> sourceRefs,
    required AiOutputOwnership ownership,
  }) {
    if (reviewState != KnowledgeCardReviewState.applied) {
      return reviewState;
    }
    final hasTraceableSource = sourceRefs.any((ref) => ref.hasEvidence);
    if (!hasTraceableSource ||
        ownership == AiOutputOwnership.aiGeneratedDraft) {
      return KnowledgeCardReviewState.approved;
    }
    return reviewState;
  }
}

class KnowledgeCardDedupe {
  const KnowledgeCardDedupe._();

  static bool isLikelyDuplicate(KnowledgeCard a, KnowledgeCard b) {
    if (_sourceHashes(a).intersection(_sourceHashes(b)).isNotEmpty) {
      return true;
    }
    if (_bookAnchors(a).intersection(_bookAnchors(b)).isNotEmpty) {
      return true;
    }
    final quoteA = normalizedQuote(a.quote);
    final quoteB = normalizedQuote(b.quote);
    if (quoteA.isNotEmpty && quoteA == quoteB) {
      return true;
    }
    final conceptsA = a.conceptRefs.map((e) => e.trim()).toSet();
    final conceptsB = b.conceptRefs.map((e) => e.trim()).toSet();
    final overlap = conceptsA.intersection(conceptsB).length;
    return overlap >= 2 && quoteA.isNotEmpty && quoteA == quoteB;
  }

  static String normalizedQuote(String quote) {
    return quote
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp('[“”"\'`]+'), '')
        .trim();
  }

  static Set<String> _sourceHashes(KnowledgeCard card) {
    return card.sourceRefs
        .map((ref) => ref.sourceHash?.trim() ?? '')
        .where((hash) => hash.isNotEmpty)
        .toSet();
  }

  static Set<String> _bookAnchors(KnowledgeCard card) {
    return card.sourceRefs
        .where((ref) => ref.bookId != null)
        .map((ref) {
          final href = ref.href?.trim() ?? '';
          final cfi = ref.cfi?.trim() ?? '';
          if (href.isEmpty && cfi.isEmpty) return '';
          return '${ref.bookId}|$href|$cfi';
        })
        .where((anchor) => anchor.isNotEmpty)
        .toSet();
  }
}
