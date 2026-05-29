import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

typedef ReviewInboxClock = int Function();

class ReviewInboxController {
  ReviewInboxController({
    Directory? rootDir,
    ReviewItemStore? reviewStore,
    KnowledgeCardStore? knowledgeCardStore,
    ConceptGraphStore? conceptGraphStore,
    SpacedReviewStore? spacedReviewStore,
    ReviewInboxClock? now,
  })  : reviewStore = reviewStore ?? ReviewItemStore(rootDir: rootDir),
        knowledgeCardStore =
            knowledgeCardStore ?? KnowledgeCardStore(rootDir: rootDir),
        conceptGraphStore =
            conceptGraphStore ?? ConceptGraphStore(rootDir: rootDir),
        spacedReviewStore =
            spacedReviewStore ?? SpacedReviewStore(rootDir: rootDir),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ReviewItemStore reviewStore;
  final KnowledgeCardStore knowledgeCardStore;
  final ConceptGraphStore conceptGraphStore;
  final SpacedReviewStore spacedReviewStore;
  final ReviewInboxClock _now;

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

    final timestamp = _now();
    final planned = item.transitionTo(
      next,
      now: timestamp,
      decisionSource: decisionSource,
    );
    final mirrorResult = await _mirrorSourceDecision(planned, now: timestamp);
    final persisted = await persist(timestamp);
    if (mirrorResult.knowledgeCardForReview case final card?) {
      await spacedReviewStore.upsertFromKnowledgeCard(card, now: timestamp);
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
      case ReviewItemSourceType.memoryCandidate:
      case ReviewItemSourceType.seminarSynthesis:
      case ReviewItemSourceType.flashcardCandidate:
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
}

class _ReviewSourceMirrorResult {
  const _ReviewSourceMirrorResult({this.knowledgeCardForReview});

  final KnowledgeCard? knowledgeCardForReview;
}
