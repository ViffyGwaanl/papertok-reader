import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';

class KnowledgeCardReviewAdapter {
  const KnowledgeCardReviewAdapter._();

  static ReviewItem fromKnowledgeCard(
    KnowledgeCard card, {
    int? now,
    ReviewItemStatus? status,
  }) {
    final createdAt =
        now ?? card.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    return ReviewItem(
      id: 'knowledge-card:${card.id}',
      sourceType: ReviewItemSourceType.knowledgeCard,
      sourceId: card.id,
      title: card.title,
      body: card.explanation,
      status: status ?? _reviewStatusForCard(card.reviewState),
      sourceRefs: card.sourceRefs,
      createdAt: createdAt,
      updatedAt: card.updatedAt ?? createdAt,
      payload: {
        'card': _safeCardPayload(card),
      },
    );
  }

  static KnowledgeCard applyReviewDecision(
    KnowledgeCard card,
    ReviewItem item, {
    int? now,
  }) {
    if (item.sourceType != ReviewItemSourceType.knowledgeCard ||
        item.sourceId != card.id) {
      throw ArgumentError('Review item does not belong to card ${card.id}.');
    }

    final nextState = _cardStateForReview(item.status);
    if (nextState == KnowledgeCardReviewState.applied &&
        !card.hasTraceableSource) {
      throw StateError('KnowledgeCard cannot be applied without SourceRef.');
    }

    final timestamp =
        now ?? item.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final nextOwnership = switch (nextState) {
      KnowledgeCardReviewState.approved ||
      KnowledgeCardReviewState.applied =>
        AiOutputOwnership.aiGeneratedApproved,
      KnowledgeCardReviewState.draft ||
      KnowledgeCardReviewState.pending ||
      KnowledgeCardReviewState.dismissed =>
        AiOutputOwnership.aiGeneratedDraft,
    };
    return card.copyWith(
      reviewState: nextState,
      ownership: nextOwnership,
      updatedAt: timestamp,
    );
  }

  static SpacedReviewItem toSpacedReviewItem(
    KnowledgeCard card, {
    required String id,
    int? dueAt,
  }) {
    if (!card.canApply) {
      throw StateError(
          'Only approved traceable cards can become review items.');
    }
    return SpacedReviewItem(
      id: id,
      cardId: card.id,
      prompt: card.title,
      answer: card.explanation,
      sourceRefs: card.sourceRefs,
      dueAt: dueAt,
    );
  }

  static ReviewItemStatus _reviewStatusForCard(KnowledgeCardReviewState state) {
    return switch (state) {
      KnowledgeCardReviewState.draft => ReviewItemStatus.pending,
      KnowledgeCardReviewState.pending => ReviewItemStatus.pending,
      KnowledgeCardReviewState.approved => ReviewItemStatus.approved,
      KnowledgeCardReviewState.dismissed => ReviewItemStatus.dismissed,
      KnowledgeCardReviewState.applied => ReviewItemStatus.applied,
    };
  }

  static KnowledgeCardReviewState _cardStateForReview(ReviewItemStatus status) {
    return switch (status) {
      ReviewItemStatus.draft => KnowledgeCardReviewState.draft,
      ReviewItemStatus.pending => KnowledgeCardReviewState.pending,
      ReviewItemStatus.approved => KnowledgeCardReviewState.approved,
      ReviewItemStatus.dismissed => KnowledgeCardReviewState.dismissed,
      ReviewItemStatus.applied => KnowledgeCardReviewState.applied,
    };
  }

  static Map<String, dynamic> _safeCardPayload(KnowledgeCard card) => {
        'id': card.id,
        'title': card.title,
        'quote': card.quote,
        'explanation': card.explanation,
        if (card.userNote != null) 'userNote': card.userNote,
        'origin': card.origin.asString,
        'conceptRefs': card.conceptRefs,
        'tags': card.tags,
      };
}

class SeminarSynthesisReviewAdapter {
  const SeminarSynthesisReviewAdapter._();

  static ReviewItem fromSynthesis({
    required String seminarId,
    required AiSeminarSynthesis synthesis,
    int? now,
  }) {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final canReview = synthesis.readyForReview && synthesis.hasTraceableHandoff;
    final sourceRefs = _sourceRefsForIds(
      synthesis.evidenceRefIds,
      synthesis.evidence,
    );
    return ReviewItem(
      id: 'seminar-synthesis:$seminarId',
      sourceType: ReviewItemSourceType.seminarSynthesis,
      sourceId: seminarId,
      title: 'AI Seminar synthesis',
      body: synthesis.summary,
      status: canReview ? ReviewItemStatus.pending : ReviewItemStatus.draft,
      sourceRefs: canReview ? sourceRefs : const <SourceRef>[],
      createdAt: timestamp,
      updatedAt: timestamp,
      payload: {
        'summary': synthesis.summary,
        'supportiveView': synthesis.supportiveView,
        'criticalView': synthesis.criticalView,
        'disagreements': synthesis.disagreements,
        'openQuestions': synthesis.openQuestions,
        'candidateReviewQuestions': synthesis.candidateReviewQuestions,
        'evidenceRefIds': synthesis.evidenceRefIds,
        'candidateCards':
            synthesis.candidateCards.map((card) => card.toJson()).toList(),
      },
    );
  }

  static List<KnowledgeCard> knowledgeCardsFromSynthesis({
    required String seminarId,
    required AiSeminarSynthesis synthesis,
    int? now,
  }) {
    if (!synthesis.readyForReview || !synthesis.hasTraceableHandoff) {
      return const <KnowledgeCard>[];
    }
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final seenCardIds = <String, int>{};
    return synthesis.candidateCards.indexed.map((indexedEntry) {
      final index = indexedEntry.$1;
      final entry = indexedEntry.$2;
      final sourceRefs = _sourceRefsForIds(
        entry.evidenceRefIds,
        synthesis.evidence,
      );
      final quote = sourceRefs
          .map((ref) => ref.sourceTextSnippet ?? '')
          .firstWhere((text) => text.trim().isNotEmpty, orElse: () => '');
      final cardId = _candidateCardId(
        seminarId: seminarId,
        entryId: entry.id,
        index: index,
        seenCardIds: seenCardIds,
      );
      return KnowledgeCard(
        id: cardId,
        title: entry.text,
        quote: quote,
        explanation: entry.text,
        sourceRefs: sourceRefs,
        reviewState: KnowledgeCardReviewState.pending,
        origin: KnowledgeCardOrigin.seminar,
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    }).toList(growable: false);
  }

  static String _candidateCardId({
    required String seminarId,
    required String entryId,
    required int index,
    required Map<String, int> seenCardIds,
  }) {
    final rawBase =
        entryId.trim().isEmpty ? 'card-${index + 1}' : entryId.trim();
    final baseId = 'seminar:$seminarId:$rawBase';
    final seen = seenCardIds[baseId] ?? 0;
    seenCardIds[baseId] = seen + 1;
    if (seen == 0) return baseId;
    return '$baseId-${seen + 1}';
  }

  static List<SourceRef> _sourceRefsForIds(
    List<String> evidenceRefIds,
    List<AiSeminarEvidence> evidence,
  ) {
    final wanted = evidenceRefIds.map((id) => id.trim()).toSet();
    return evidence
        .where((item) => wanted.contains(item.id.trim()))
        .map((item) => item.sourceRef)
        .where((ref) => ref.hasEvidence)
        .toList(growable: false);
  }
}

class MemoryCandidateReviewAdapter {
  const MemoryCandidateReviewAdapter._();

  static ReviewItem fromMemoryCandidate(MemoryCandidate candidate) {
    return ReviewItem(
      id: 'memory-candidate:${candidate.id}',
      sourceType: ReviewItemSourceType.memoryCandidate,
      sourceId: candidate.id,
      title: candidate.summary,
      body: candidate.effectiveDisplayText,
      status: _reviewStatusForMemory(candidate.status),
      sourceRefs: [
        if (_sourceRefForMemoryCandidate(candidate) case final ref?) ref,
      ],
      createdAt: candidate.createdAtMs,
      updatedAt: candidate.reviewedAtMs ?? candidate.createdAtMs,
      decidedAt: candidate.reviewedAtMs,
      appliedAt: candidate.appliedAtMs,
      decisionSource: candidate.decisionSource,
      payload: {
        'targetDoc': candidate.targetDoc.name,
        if (candidate.appliedTargetDoc != null)
          'appliedTargetDoc': candidate.appliedTargetDoc!.name,
        'sourceType': candidate.sourceType,
        'sensitivity': candidate.sensitivity,
        if (candidate.confidence != null) 'confidence': candidate.confidence,
        if (candidate.sourcePointer != null)
          'sourcePointer': candidate.sourcePointer,
        if (candidate.rationale != null) 'rationale': candidate.rationale,
      },
    );
  }

  static ReviewItemStatus _reviewStatusForMemory(MemoryCandidateStatus status) {
    return switch (status) {
      MemoryCandidateStatus.pending => ReviewItemStatus.pending,
      MemoryCandidateStatus.applied => ReviewItemStatus.applied,
      MemoryCandidateStatus.dismissed => ReviewItemStatus.dismissed,
    };
  }

  static SourceRef? _sourceRefForMemoryCandidate(MemoryCandidate candidate) {
    final hasBookAnchor =
        candidate.bookId != null && (candidate.cfi ?? '').trim().isNotEmpty;
    final hasText = candidate.effectiveDisplayText.trim().isNotEmpty;
    if (!hasBookAnchor && !hasText) return null;
    return SourceRef(
      bookId: candidate.bookId,
      cfi: candidate.cfi,
      jumpLink: hasBookAnchor
          ? PaperReaderReaderIntent(
              bookId: candidate.bookId!,
              cfi: candidate.cfi,
            ).toUri().toString()
          : null,
      sourceTitle: candidate.chapter,
      locationLabel: candidate.effectiveSourcePointer,
      sourceTextSnippet: candidate.effectiveDisplayText,
      sourceTextForHash: candidate.text,
      sourceKind: SourceRefKind.memory,
      confidence: candidate.confidence,
    );
  }
}

class BookNoteSourceRefAdapter {
  const BookNoteSourceRefAdapter._();

  static SourceRef fromBookNote(BookNote note, {String? sourceTitle}) {
    final kind = switch (note.type.trim()) {
      'highlight' || 'underline' => SourceRefKind.highlight,
      _ => SourceRefKind.note,
    };
    final hasCfi = note.cfi.trim().isNotEmpty;
    return SourceRef(
      bookId: note.bookId,
      cfi: note.cfi,
      jumpLink: hasCfi
          ? PaperReaderReaderIntent(bookId: note.bookId, cfi: note.cfi)
              .toUri()
              .toString()
          : null,
      sourceTitle: sourceTitle,
      locationLabel: note.chapter,
      sourceTextSnippet: note.content,
      sourceTextForHash:
          '${note.id ?? ''}|${note.content}|${note.readerNote ?? ''}',
      sourceKind: kind,
      createdAt: note.createTime?.millisecondsSinceEpoch,
    );
  }
}

class FlashcardReviewAdapter {
  const FlashcardReviewAdapter._();

  static ReviewItem fromFlashcardCandidate({
    required String id,
    required String prompt,
    required String answer,
    List<SourceRef> sourceRefs = const <SourceRef>[],
    int? now,
  }) {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    return ReviewItem(
      id: 'flashcard:$id',
      sourceType: ReviewItemSourceType.flashcardCandidate,
      sourceId: id,
      title: prompt,
      body: answer,
      status: ReviewItemStatus.pending,
      sourceRefs: sourceRefs,
      createdAt: timestamp,
      updatedAt: timestamp,
      payload: {
        'prompt': prompt,
        'answer': answer,
      },
    );
  }

  static SpacedReviewItem toSpacedReviewItem(
    ReviewItem item, {
    required String id,
    int? dueAt,
  }) {
    if (item.sourceType != ReviewItemSourceType.flashcardCandidate) {
      throw ArgumentError('Review item is not a flashcard candidate.');
    }
    if (item.status != ReviewItemStatus.approved || !item.hasTraceableSource) {
      throw StateError(
        'Only approved traceable flashcards can become spaced review items.',
      );
    }
    return SpacedReviewItem(
      id: id,
      cardId: item.sourceId,
      prompt: (item.payload['prompt'] ?? item.title).toString(),
      answer: (item.payload['answer'] ?? item.body).toString(),
      sourceRefs: item.sourceRefs,
      dueAt: dueAt,
    );
  }
}

class ConceptGraphReviewAdapter {
  const ConceptGraphReviewAdapter._();

  static ReviewItem fromRelation(
    ConceptEdge edge, {
    int? now,
    ReviewItemStatus? status,
  }) {
    final timestamp =
        now ?? edge.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final label = edge.label?.trim();
    final title = label == null || label.isEmpty
        ? '${edge.sourceNodeId} ${edge.type.asString} ${edge.targetNodeId}'
        : label;
    return ReviewItem(
      id: 'concept-graph-relation:${edge.id}',
      sourceType: ReviewItemSourceType.conceptGraphRelation,
      sourceId: edge.id,
      title: title,
      body:
          '${edge.sourceNodeId} --${edge.type.asString}--> ${edge.targetNodeId}',
      status: status ?? ReviewItemStatus.pending,
      sourceRefs: edge.evidenceRefs.where((ref) => ref.hasEvidence).toList(),
      createdAt: timestamp,
      updatedAt: edge.updatedAt ?? timestamp,
      payload: {
        'edge': {
          'id': edge.id,
          'sourceNodeId': edge.sourceNodeId,
          'targetNodeId': edge.targetNodeId,
          'type': edge.type.asString,
          if (edge.label != null) 'label': edge.label,
          if (edge.confidence != null) 'confidence': edge.confidence,
        },
      },
    );
  }

  static ConceptEdge applyReviewDecision(
    ConceptEdge edge,
    ReviewItem item, {
    int? now,
  }) {
    if (item.sourceType != ReviewItemSourceType.conceptGraphRelation ||
        item.sourceId != edge.id) {
      throw ArgumentError('Review item does not belong to edge ${edge.id}.');
    }
    if (item.status == ReviewItemStatus.applied && !edge.hasEvidence) {
      throw StateError('ConceptGraph relation cannot apply without evidence.');
    }

    final timestamp =
        now ?? item.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final ownership = item.status == ReviewItemStatus.applied
        ? AiOutputOwnership.aiGeneratedApproved
        : AiOutputOwnership.aiGeneratedDraft;
    return ConceptEdge(
      id: edge.id,
      sourceNodeId: edge.sourceNodeId,
      targetNodeId: edge.targetNodeId,
      type: edge.type,
      label: edge.label,
      evidenceRefs: edge.evidenceRefs,
      confidence: edge.confidence,
      ownership: ownership,
      createdAt: edge.createdAt,
      updatedAt: timestamp,
    );
  }
}
