import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

void main() {
  late Directory tempRoot;
  late ReviewItemStore reviewStore;
  late KnowledgeCardStore cardStore;
  late ConceptGraphStore graphStore;
  late SpacedReviewStore spacedReviewStore;
  late ReviewInboxController controller;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'review_inbox_controller_',
    );
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    graphStore = ConceptGraphStore(rootDir: tempRoot);
    spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    controller = ReviewInboxController(
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      conceptGraphStore: graphStore,
      spacedReviewStore: spacedReviewStore,
      now: () => 1000,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 7,
    String href = 'Text/chapter.xhtml',
    String cfi = 'epubcfi(/6/8)',
    String snippet = 'Evidence passage.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: href,
        cfi: cfi,
        jumpLink: 'paperreader://reader/open?bookId=$bookId&cfi=$cfi',
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({
    String id = 'kc-1',
    List<SourceRef>? sourceRefs,
    List<String> conceptRefs = const <String>[],
  }) {
    return KnowledgeCard(
      id: id,
      title: 'Attention bottleneck',
      quote: 'Evidence passage.',
      explanation: 'Readers need a durable card with source traceability.',
      conceptRefs: conceptRefs,
      sourceRefs: sourceRefs ?? [traceableRef()],
      origin: KnowledgeCardOrigin.seminar,
      reviewState: KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: 100,
      updatedAt: 100,
    );
  }

  Future<ReviewItem> stageCardForReview(
    String id, {
    List<String> conceptRefs = const <String>[],
  }) async {
    final staged = await cardStore.upsertCandidate(
      card(id: id, conceptRefs: conceptRefs),
    );
    final item = KnowledgeCardReviewAdapter.fromKnowledgeCard(staged.card);
    return reviewStore.upsert(item);
  }

  Future<ReviewItem> stageConceptRelationForReview(String id) async {
    await graphStore.upsertNode(
      ConceptNode(
        id: 'n1',
        type: ConceptNodeType.concept,
        label: 'Reading',
        sourceRefs: [traceableRef()],
      ),
    );
    await graphStore.upsertNode(
      ConceptNode(
        id: 'n2',
        type: ConceptNodeType.claim,
        label: 'Review',
        sourceRefs: [traceableRef(snippet: 'Review evidence.')],
      ),
    );
    final relation = await graphStore.upsertEdge(
      ConceptEdge(
        id: id,
        sourceNodeId: 'n1',
        targetNodeId: 'n2',
        type: ConceptEdgeType.supports,
        evidenceRefs: [traceableRef()],
      ),
    );
    return reviewStore.upsert(
      ConceptGraphReviewAdapter.fromRelation(relation),
    );
  }

  test('approve and apply mirror knowledge card review state', () async {
    await stageCardForReview('kc-apply');

    final approved = await controller.approve('knowledge-card:kc-apply');
    final approvedCard = await cardStore.getById('kc-apply');
    final applied = await controller.apply('knowledge-card:kc-apply');
    final appliedCard = await cardStore.getById('kc-apply');

    expect(approved.status, ReviewItemStatus.approved);
    expect(approved.decidedAt, 1000);
    expect(approvedCard!.reviewState, KnowledgeCardReviewState.approved);
    expect(approvedCard.ownership, AiOutputOwnership.aiGeneratedApproved);
    expect(applied.status, ReviewItemStatus.applied);
    expect(applied.appliedAt, 1000);
    expect(appliedCard!.reviewState, KnowledgeCardReviewState.applied);
    expect(appliedCard.isUserAsset, true);
  });

  test('knowledge card apply creates a single spaced review item', () async {
    await stageCardForReview('kc-spaced');

    await controller.approve('knowledge-card:kc-spaced');
    await controller.apply('knowledge-card:kc-spaced');
    final reviewItems = await spacedReviewStore.list();

    expect(reviewItems, hasLength(1));
    expect(
      reviewItems.single.id,
      SpacedReviewStore.reviewIdForCard('kc-spaced'),
    );
    expect(reviewItems.single.cardId, 'kc-spaced');
    expect(reviewItems.single.sourceRefs.single.hasEvidence, true);
  });

  test('flashcard candidate apply creates a spaced review item', () async {
    final item = FlashcardReviewAdapter.fromFlashcardCandidate(
      id: 'flash-apply',
      prompt: 'What makes evidence durable?',
      answer: 'A SourceRef and jump link.',
      sourceRefs: [traceableRef()],
      now: 100,
    );
    await reviewStore.upsert(item);

    await controller.approve('flashcard:flash-apply');
    final applied = await controller.apply('flashcard:flash-apply');
    final reviewItems = await spacedReviewStore.list();

    expect(applied.status, ReviewItemStatus.applied);
    expect(reviewItems, hasLength(1));
    expect(
      reviewItems.single.id,
      SpacedReviewStore.reviewIdForFlashcard('flash-apply'),
    );
    expect(reviewItems.single.cardId, 'flash-apply');
    expect(reviewItems.single.prompt, 'What makes evidence durable?');
    expect(reviewItems.single.answer, 'A SourceRef and jump link.');
    expect(reviewItems.single.sourceRefs.single.hasEvidence, true);
  });

  test('knowledge card apply creates draft concept graph candidates', () async {
    await stageCardForReview(
      'kc-graph',
      conceptRefs: const ['Attention', 'Review'],
    );

    await controller.approve('knowledge-card:kc-graph');
    await controller.apply('knowledge-card:kc-graph');

    final nodes = await graphStore.listNodes();
    final edges = await graphStore.listEdges();
    final conceptReviewItems = await reviewStore.list(
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );

    expect(nodes.map((node) => node.id), contains('card:kc-graph'));
    expect(nodes.map((node) => node.id), contains('concept:attention'));
    expect(nodes.map((node) => node.id), contains('concept:review'));
    expect(
        nodes.every(
            (node) => node.ownership == AiOutputOwnership.aiGeneratedDraft),
        isTrue);
    expect(edges, hasLength(2));
    expect(edges.every((edge) => edge.hasEvidence), isTrue);
    expect(edges.every((edge) => edge.isFormal), isFalse);
    expect(conceptReviewItems, hasLength(2));
    expect(
      conceptReviewItems.every(
        (item) =>
            item.status == ReviewItemStatus.pending && item.hasTraceableSource,
      ),
      isTrue,
    );
  });

  test('concept graph producer failure does not roll back card apply',
      () async {
    final failingController = ReviewInboxController(
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      conceptGraphStore: graphStore,
      spacedReviewStore: spacedReviewStore,
      conceptGraphProducer: _FailingConceptGraphProducer(),
      now: () => 1000,
    );
    await stageCardForReview(
      'kc-graph-fail',
      conceptRefs: const ['Attention'],
    );

    final approved =
        await failingController.approve('knowledge-card:kc-graph-fail');
    final applied =
        await failingController.apply('knowledge-card:kc-graph-fail');
    final appliedCard = await cardStore.getById('kc-graph-fail');

    expect(approved.status, ReviewItemStatus.approved);
    expect(applied.status, ReviewItemStatus.applied);
    expect(appliedCard!.isUserAsset, true);
    expect(await spacedReviewStore.list(), hasLength(1));
    expect(await graphStore.listEdges(), isEmpty);
  });

  test('dismiss mirrors knowledge card without creating a user asset',
      () async {
    await stageCardForReview('kc-dismiss');

    final dismissed = await controller.dismiss('knowledge-card:kc-dismiss');
    final dismissedCard = await cardStore.getById('kc-dismiss');

    expect(dismissed.status, ReviewItemStatus.dismissed);
    expect(dismissed.decidedAt, 1000);
    expect(dismissedCard!.reviewState, KnowledgeCardReviewState.dismissed);
    expect(dismissedCard.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(dismissedCard.isUserAsset, false);
    expect(await spacedReviewStore.list(), isEmpty);
  });

  test('unsupported source types cannot be generically applied', () async {
    final item = ReviewItem(
      id: 'seminar-synthesis:s1',
      sourceType: ReviewItemSourceType.seminarSynthesis,
      sourceId: 's1',
      title: 'Seminar synthesis',
      body: 'A source-backed synthesis still needs a source-specific adapter.',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);
    await controller.approve('seminar-synthesis:s1');

    expect(
      () => controller.apply('seminar-synthesis:s1'),
      throwsUnsupportedError,
    );
    final unchanged = await reviewStore.getById('seminar-synthesis:s1');
    expect(unchanged!.status, ReviewItemStatus.approved);
    expect(unchanged.appliedAt, isNull);
  });

  test('sync conflict review cannot be approved without a resolution adapter',
      () async {
    final item = ReviewItem(
      id: 'sync-conflict:kc-conflict',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'kc-conflict',
      title: 'Sync conflict: kc-conflict',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);

    expect(
      () => controller.approve('sync-conflict:kc-conflict'),
      throwsUnsupportedError,
    );
    final unchanged = await reviewStore.getById('sync-conflict:kc-conflict');
    expect(unchanged!.status, ReviewItemStatus.pending);
    expect(unchanged.decidedAt, isNull);
  });

  test('apply mirrors concept graph relation source state', () async {
    await stageConceptRelationForReview('edge-apply');

    await controller.approve('concept-graph-relation:edge-apply');
    final applied = await controller.apply(
      'concept-graph-relation:edge-apply',
    );
    final restoredEdge = (await graphStore.listEdges())
        .singleWhere((edge) => edge.id == 'edge-apply');

    expect(applied.status, ReviewItemStatus.applied);
    expect(restoredEdge.isFormal, true);
    expect(restoredEdge.ownership, AiOutputOwnership.aiGeneratedApproved);
  });

  test('source failure does not advance the review item', () async {
    final missingCardItem = ReviewItem(
      id: 'knowledge-card:missing',
      sourceType: ReviewItemSourceType.knowledgeCard,
      sourceId: 'missing',
      title: 'Missing source card',
      body: 'This review item points at a missing card.',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(missingCardItem);

    expect(
      () => controller.approve('knowledge-card:missing'),
      throwsStateError,
    );
    final unchanged = await reviewStore.getById('knowledge-card:missing');
    expect(unchanged!.status, ReviewItemStatus.pending);
    expect(unchanged.decidedAt, isNull);
  });

  test('source jump audit separates jumpable, unavailable, and unresolved refs',
      () async {
    final item = ReviewItem(
      id: 'review-audit',
      sourceType: ReviewItemSourceType.seminarSynthesis,
      sourceId: 'seminar-1',
      title: 'Audit',
      body: 'Audit source links.',
      status: ReviewItemStatus.pending,
      sourceRefs: [
        traceableRef(),
        SourceRef(
          sourceTextForHash: 'hash-only evidence',
          sourceKind: SourceRefKind.conversation,
        ),
        SourceRef(
          unavailableReason: 'Source document was deleted.',
          sourceKind: SourceRefKind.libraryRag,
        ),
      ],
    );

    final audit = controller.sourceJumpAudit(item);

    expect(audit.jumpableCount, 1);
    expect(audit.unavailableCount, 1);
    expect(audit.unresolvedIndexes, [1]);
    expect(audit.allResolved, false);
  });
}

class _FailingConceptGraphProducer extends ConceptGraphProducer {
  @override
  Future<ConceptGraphProducerResult> createFromKnowledgeCard(
    KnowledgeCard card,
  ) {
    throw StateError('graph unavailable');
  }
}
