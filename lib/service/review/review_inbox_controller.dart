import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

typedef ReviewInboxClock = int Function();

class ReviewInboxController {
  ReviewInboxController({
    Directory? rootDir,
    ReviewItemStore? reviewStore,
    KnowledgeCardStore? knowledgeCardStore,
    ConceptGraphStore? conceptGraphStore,
    ConceptGraphProducer? conceptGraphProducer,
    SpacedReviewStore? spacedReviewStore,
    MemoryWorkflowService? memoryWorkflowService,
    ReviewInboxClock? now,
  })  : reviewStore = reviewStore ?? ReviewItemStore(rootDir: rootDir),
        knowledgeCardStore =
            knowledgeCardStore ?? KnowledgeCardStore(rootDir: rootDir),
        conceptGraphStore =
            conceptGraphStore ?? ConceptGraphStore(rootDir: rootDir),
        conceptGraphProducer = conceptGraphProducer ??
            ConceptGraphProducer(
              rootDir: rootDir,
              graphStore: conceptGraphStore,
              reviewStore: reviewStore,
              now: now,
            ),
        spacedReviewStore =
            spacedReviewStore ?? SpacedReviewStore(rootDir: rootDir),
        memoryWorkflowService =
            memoryWorkflowService ?? _defaultMemoryWorkflowService(rootDir),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ReviewItemStore reviewStore;
  final KnowledgeCardStore knowledgeCardStore;
  final ConceptGraphStore conceptGraphStore;
  final ConceptGraphProducer conceptGraphProducer;
  final SpacedReviewStore spacedReviewStore;
  final MemoryWorkflowService memoryWorkflowService;
  final ReviewInboxClock _now;

  static MemoryWorkflowService _defaultMemoryWorkflowService(
    Directory? rootDir,
  ) {
    return MemoryWorkflowService(
      store: MarkdownMemoryStore(rootDir: rootDir),
    );
  }

  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) {
    return reviewStore.list(status: status, sourceType: sourceType);
  }

  Future<ReviewItem?> getById(String id) => reviewStore.getById(id);

  Future<ReviewItem> submit(String id) {
    return _transition(
      id,
      ReviewItemStatus.pending,
      decisionSource: null,
      persist: (timestamp) => reviewStore.submit(id, now: timestamp),
    );
  }

  Future<ReviewItem> approve(String id) {
    const decisionSource = 'user_approve';
    return _transition(
      id,
      ReviewItemStatus.approved,
      decisionSource: decisionSource,
      persist: (timestamp) => reviewStore.approve(
        id,
        now: timestamp,
        decisionSource: decisionSource,
      ),
    );
  }

  Future<ReviewItem> dismiss(String id) {
    const decisionSource = 'user_dismiss';
    return _transition(
      id,
      ReviewItemStatus.dismissed,
      decisionSource: decisionSource,
      persist: (timestamp) => reviewStore.dismiss(
        id,
        now: timestamp,
        decisionSource: decisionSource,
      ),
    );
  }

  Future<ReviewItem> apply(String id) {
    const decisionSource = 'user_apply';
    return _transition(
      id,
      ReviewItemStatus.applied,
      decisionSource: decisionSource,
      persist: (timestamp) => reviewStore.apply(
        id,
        now: timestamp,
        decisionSource: decisionSource,
      ),
    );
  }

  PaperReaderSourceJumpAudit sourceJumpAudit(ReviewItem item) {
    return PaperReaderSourceJumpAudit.fromSourceRefs(item.sourceRefs);
  }

  Future<ReviewItem> _transition(
    String id,
    ReviewItemStatus next, {
    required String? decisionSource,
    required Future<ReviewItem> Function(int timestamp) persist,
  }) async {
    final item = await reviewStore.getById(id);
    if (item == null) {
      throw StateError('Review item not found: $id');
    }
    if (next == ReviewItemStatus.approved &&
        item.sourceType == ReviewItemSourceType.syncConflict &&
        !_canResolveSyncConflict(item)) {
      throw UnsupportedError(
        'Sync conflict review cannot be approved without a resolution adapter.',
      );
    }

    final timestamp = _now();
    final planned = item.transitionTo(
      next,
      now: timestamp,
      decisionSource: decisionSource,
    );
    final mirrorResult = await _mirrorSourceDecision(planned, now: timestamp);
    final persisted = await _persistTransitionAfterSourceMirror(
      item,
      next,
      timestamp: timestamp,
      decisionSource: decisionSource,
      persist: persist,
    );
    if (mirrorResult.knowledgeCardForReview case final card?) {
      await spacedReviewStore.upsertFromKnowledgeCard(card, now: timestamp);
      try {
        await conceptGraphProducer.createFromKnowledgeCard(card);
      } catch (_) {
        // Concept graph candidates are a recoverable side effect of Review
        // apply. The applied card and spaced review item remain authoritative.
      }
    }
    if (mirrorResult.flashcardForReview case final flashcard?) {
      await spacedReviewStore.upsertFromFlashcardReviewItem(
        flashcard,
        now: timestamp,
      );
    }
    return persisted;
  }

  Future<_ReviewSourceMirrorResult> _mirrorSourceDecision(
    ReviewItem item, {
    required int now,
  }) async {
    switch (item.sourceType) {
      case ReviewItemSourceType.knowledgeCard:
        final card = await knowledgeCardStore.applyReviewDecision(
          item,
          now: now,
        );
        return _ReviewSourceMirrorResult(
          knowledgeCardForReview:
              item.status == ReviewItemStatus.applied ? card : null,
        );
      case ReviewItemSourceType.conceptGraphRelation:
        await conceptGraphStore.applyReviewDecision(item, now: now);
        return const _ReviewSourceMirrorResult();
      case ReviewItemSourceType.flashcardCandidate:
        FlashcardReviewAdapter.toSpacedReviewItem(
          item,
          id: SpacedReviewStore.reviewIdForFlashcard(item.sourceId),
          dueAt: now,
        );
        return _ReviewSourceMirrorResult(
          flashcardForReview:
              item.status == ReviewItemStatus.applied ? item : null,
        );
      case ReviewItemSourceType.syncConflict:
        if (!_canResolveSyncConflict(item)) {
          if (item.status == ReviewItemStatus.approved ||
              item.status == ReviewItemStatus.applied) {
            throw UnsupportedError(
              'Review apply is not implemented for this sync conflict.',
            );
          }
          return const _ReviewSourceMirrorResult();
        }
        if (item.status == ReviewItemStatus.applied) {
          await knowledgeCardStore.resolveSyncConflict(
            item.sourceId,
            stagedConflictId: _stagedSyncConflictId(item),
            now: now,
          );
        }
        return const _ReviewSourceMirrorResult();
      case ReviewItemSourceType.memoryCandidate:
        if (item.status == ReviewItemStatus.dismissed) {
          await memoryWorkflowService.dismissCandidate(item.sourceId);
          return const _ReviewSourceMirrorResult();
        }
        if (item.status == ReviewItemStatus.applied) {
          await memoryWorkflowService.applyCandidate(
            item.sourceId,
            targetDoc: _memoryTargetDocFor(item),
          );
          return const _ReviewSourceMirrorResult();
        }
        return const _ReviewSourceMirrorResult();
      case ReviewItemSourceType.reviewHistoryImport:
        if (item.status == ReviewItemStatus.applied) {
          await spacedReviewStore.upsertImportedReviewHistory(
            _reviewHistoryImportItem(item),
            now: now,
          );
        }
        return const _ReviewSourceMirrorResult();
      case ReviewItemSourceType.seminarSynthesis:
      case ReviewItemSourceType.imageAnalysisCard:
      case ReviewItemSourceType.unknown:
        if (item.status == ReviewItemStatus.applied) {
          throw UnsupportedError(
            'Review apply is not implemented for source type '
            '${item.sourceType.asString}.',
          );
        }
        return const _ReviewSourceMirrorResult();
    }
  }

  bool _canResolveSyncConflict(ReviewItem item) {
    return item.sourceType == ReviewItemSourceType.syncConflict &&
        item.payload['canApply'] == true;
  }

  String? _stagedSyncConflictId(ReviewItem item) {
    if (item.payload['remoteStaged'] != true) return null;
    final id = item.payload['stagedConflictId']?.toString().trim();
    if (id == null || id.isEmpty) {
      throw StateError('Remote staged sync conflict is missing staged id.');
    }
    return id;
  }

  Future<ReviewItem> _persistTransitionAfterSourceMirror(
    ReviewItem original,
    ReviewItemStatus next, {
    required int timestamp,
    required String? decisionSource,
    required Future<ReviewItem> Function(int timestamp) persist,
  }) {
    if (next == ReviewItemStatus.applied &&
        original.sourceType == ReviewItemSourceType.syncConflict &&
        _canResolveSyncConflict(original)) {
      return reviewStore.applyResolvedSyncConflict(
        original.id,
        now: timestamp,
        decisionSource: decisionSource ?? 'user_apply',
      );
    }
    if (next == ReviewItemStatus.applied &&
        original.sourceType == ReviewItemSourceType.memoryCandidate) {
      return reviewStore.applyResolvedMemoryCandidate(
        original.id,
        now: timestamp,
        decisionSource: decisionSource ?? 'user_apply',
      );
    }
    if (next == ReviewItemStatus.applied &&
        original.sourceType == ReviewItemSourceType.reviewHistoryImport) {
      return reviewStore.applyResolvedReviewHistoryImport(
        original.id,
        now: timestamp,
        decisionSource: decisionSource ?? 'user_apply',
      );
    }
    return persist(timestamp);
  }

  SpacedReviewItem _reviewHistoryImportItem(ReviewItem item) {
    final raw = item.payload['reviewHistoryItem'];
    if (raw is! Map) {
      throw StateError('Review history import is missing payload.');
    }
    final reviewItem = SpacedReviewItem.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (reviewItem.id != item.sourceId) {
      throw StateError('Review history import source id mismatch.');
    }
    if (!reviewItem.sourceRefs.any((ref) => ref.hasEvidence)) {
      throw StateError('Review history import cannot apply without SourceRef.');
    }
    return reviewItem;
  }

  MemoryDocTarget _memoryTargetDocFor(ReviewItem item) {
    final rawTarget =
        (item.payload['appliedTargetDoc'] ?? item.payload['targetDoc'])
            ?.toString();
    for (final target in MemoryDocTarget.values) {
      if (target.name == rawTarget) return target;
    }
    throw StateError(
      'Memory candidate review is missing a valid targetDoc: ${item.id}',
    );
  }
}

class _ReviewSourceMirrorResult {
  const _ReviewSourceMirrorResult({
    this.knowledgeCardForReview,
    this.flashcardForReview,
  });

  final KnowledgeCard? knowledgeCardForReview;
  final ReviewItem? flashcardForReview;
}
