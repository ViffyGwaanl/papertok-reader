import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
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
  late MarkdownMemoryStore memoryStore;
  late MemoryCandidateStore memoryCandidateStore;
  late ReviewInboxController controller;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'review_inbox_controller_',
    );
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    graphStore = ConceptGraphStore(rootDir: tempRoot);
    spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    memoryStore = MarkdownMemoryStore(rootDir: tempRoot);
    memoryCandidateStore = MemoryCandidateStore(rootDir: tempRoot);
    controller = ReviewInboxController(
      rootDir: tempRoot,
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

  Future<ReviewItem> stageMemoryCandidateForReview(
    String id, {
    MemoryDocTarget targetDoc = MemoryDocTarget.longTerm,
    String text = 'Remember current-book evidence before library search.',
  }) async {
    const cfi = 'epubcfi(/6/8!/4/2/12:5)';
    final candidate = MemoryCandidate(
      id: id,
      summary: 'Memory review candidate',
      text: text,
      targetDoc: targetDoc,
      sourceType: 'session_digest',
      createdAtMs: 100,
      status: MemoryCandidateStatus.pending,
      displayText: text,
      sourcePointer: 'Chapter 2',
      bookId: 7,
      cfi: cfi,
      chapter: 'Evidence chapter',
      sourceKind: MemorySourceKind.reading,
    );
    await memoryCandidateStore.upsert(candidate);
    return reviewStore.upsert(
      MemoryCandidateReviewAdapter.fromMemoryCandidate(candidate),
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

  test(
      'memory candidate apply writes target memory doc and advances both stores',
      () async {
    await stageMemoryCandidateForReview('mem-apply');

    await controller.approve('memory-candidate:mem-apply');
    final applied = await controller.apply('memory-candidate:mem-apply');
    final storedCandidate = await memoryCandidateStore.getById('mem-apply');
    final longTerm = await memoryStore.read(longTerm: true);
    final daily = await memoryStore.read(longTerm: false);

    expect(applied.status, ReviewItemStatus.applied);
    expect(applied.decisionSource, 'user_apply');
    expect(applied.appliedAt, 1000);
    expect(storedCandidate!.status, MemoryCandidateStatus.applied);
    expect(storedCandidate.appliedTargetDoc, MemoryDocTarget.longTerm);
    expect(storedCandidate.decisionSource, 'user_apply');
    expect(
      longTerm,
      contains('Remember current-book evidence before library search.'),
    );
    expect(
      daily,
      isNot(contains('Remember current-book evidence before library search.')),
    );
    expect(await spacedReviewStore.list(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
  });

  test(
      'memory candidate dismiss mirrors source candidate without writing memory',
      () async {
    await stageMemoryCandidateForReview(
      'mem-dismiss',
      text: 'Do not keep this memory candidate.',
    );

    final dismissed = await controller.dismiss('memory-candidate:mem-dismiss');
    final storedCandidate = await memoryCandidateStore.getById('mem-dismiss');
    final longTerm = await memoryStore.read(longTerm: true);

    expect(dismissed.status, ReviewItemStatus.dismissed);
    expect(dismissed.decisionSource, 'user_dismiss');
    expect(storedCandidate!.status, MemoryCandidateStatus.dismissed);
    expect(storedCandidate.decisionSource, 'user_dismiss');
    expect(longTerm, isNot(contains('Do not keep this memory candidate.')));
  });

  test('memory candidate source failure does not advance review item',
      () async {
    final item = ReviewItem(
      id: 'memory-candidate:missing',
      sourceType: ReviewItemSourceType.memoryCandidate,
      sourceId: 'missing',
      title: 'Missing memory candidate',
      body: 'The source candidate was removed before apply.',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);
    await controller.approve(item.id);

    expect(
      () => controller.apply(item.id),
      throwsA(isA<StateError>()),
    );
    final unchanged = await reviewStore.getById(item.id);
    final longTerm = await memoryStore.read(longTerm: true);

    expect(unchanged!.status, ReviewItemStatus.approved);
    expect(unchanged.appliedAt, isNull);
    expect(longTerm.trim(), isEmpty);
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

  test('safe sync conflict approve and apply resolves knowledge card',
      () async {
    final conflictCard = card(
      id: 'kc-safe-conflict',
      sourceRefs: [traceableRef()],
    ).copyWith(
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [
          KnowledgeSyncEnvelope(
            id: conflictCard.id,
            entityType: KnowledgeSyncEntityType.knowledgeCard,
            schemaVersion: 1,
            updatedAt: 200,
            conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
            conflictReason: 'content-conflict',
            sourceRefs: conflictCard.sourceRefs,
            payload: conflictCard.toJson(),
          ).toJson(),
        ],
      }),
    );
    final item = ReviewItem(
      id: 'sync-conflict:kc-safe-conflict',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'kc-safe-conflict',
      title: 'Sync conflict: kc-safe-conflict',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.pending,
      sourceRefs: conflictCard.sourceRefs,
      payload: const {'canApply': true},
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);

    final approved = await controller.approve(item.id);
    final applied = await controller.apply(item.id);
    final envelopes = await cardStore.listSyncEnvelopes();

    expect(approved.status, ReviewItemStatus.approved);
    expect(applied.status, ReviewItemStatus.applied);
    expect(envelopes.single.requiresConflictReview, false);
    expect(envelopes.single.entityType, KnowledgeSyncEntityType.knowledgeCard);
    expect(await spacedReviewStore.list(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
  });

  test(
      'batch applies approved safe sync conflicts and leaves failures retryable',
      () async {
    final localConflictCard = card(
      id: 'kc-batch-local',
      sourceRefs: [traceableRef()],
    ).copyWith(
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [
          KnowledgeSyncEnvelope(
            id: localConflictCard.id,
            entityType: KnowledgeSyncEntityType.knowledgeCard,
            schemaVersion: 1,
            updatedAt: 200,
            conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
            conflictReason: 'content-conflict',
            sourceRefs: localConflictCard.sourceRefs,
            payload: localConflictCard.toJson(),
          ).toJson(),
        ],
      }),
    );
    final localItem = ReviewItem(
      id: 'sync-conflict:${localConflictCard.id}',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: localConflictCard.id,
      title: 'Sync conflict: ${localConflictCard.id}',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.approved,
      sourceRefs: localConflictCard.sourceRefs,
      payload: const {'canApply': true},
      createdAt: 100,
      updatedAt: 100,
    );
    final missingRemoteItem = ReviewItem(
      id: 'sync-conflict-remote-staged:kc-batch-remote',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'kc-batch-remote',
      title: 'Sync conflict: kc-batch-remote',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.approved,
      sourceRefs: [traceableRef(snippet: 'Remote conflict evidence.')],
      payload: const {
        'canApply': true,
        'remoteStaged': true,
        'stagedConflictId': 'kc-batch-remote',
      },
      createdAt: 100,
      updatedAt: 100,
    );
    final previewOnlyItem = ReviewItem(
      id: 'sync-conflict:preview-only',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'preview-only',
      title: 'Sync conflict: preview-only',
      body: 'Conflict reason: preview-only',
      status: ReviewItemStatus.approved,
      sourceRefs: [traceableRef(snippet: 'Preview evidence.')],
      payload: const {
        'canApply': false,
        'remotePreviewOnly': true,
      },
      createdAt: 100,
      updatedAt: 100,
    );
    final unavailableOnlyItem = ReviewItem(
      id: 'sync-conflict:unavailable-only',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'unavailable-only',
      title: 'Sync conflict: unavailable-only',
      body: 'Conflict reason: source-missing',
      status: ReviewItemStatus.approved,
      sourceRefs: [
        SourceRef(
          sourceKind: SourceRefKind.unknown,
          unavailableReason: 'sync-conflict-no-source',
        ),
      ],
      payload: const {'canApply': true},
      createdAt: 100,
      updatedAt: 100,
    );
    Future<void> upsertApproved(ReviewItem item) async {
      await reviewStore.upsert(item.copyWith(status: ReviewItemStatus.pending));
      await reviewStore.approve(item.id, now: 150);
    }

    await upsertApproved(localItem);
    await upsertApproved(missingRemoteItem);
    await upsertApproved(previewOnlyItem);
    await upsertApproved(unavailableOnlyItem);

    final firstRun = await controller.applyApprovedSyncConflicts();
    final localAfterFirstRun = await reviewStore.getById(localItem.id);
    final missingAfterFirstRun =
        await reviewStore.getById(missingRemoteItem.id);
    final previewAfterFirstRun = await reviewStore.getById(previewOnlyItem.id);
    final unavailableAfterFirstRun =
        await reviewStore.getById(unavailableOnlyItem.id);

    expect(firstRun.appliedIds, [localItem.id]);
    expect(firstRun.failed.single.id, missingRemoteItem.id);
    expect(localAfterFirstRun?.status, ReviewItemStatus.applied);
    expect(missingAfterFirstRun?.status, ReviewItemStatus.approved);
    expect(missingAfterFirstRun?.appliedAt, isNull);
    expect(previewAfterFirstRun?.status, ReviewItemStatus.approved);
    expect(unavailableAfterFirstRun?.status, ReviewItemStatus.approved);

    final remoteConflictCard = card(
      id: 'kc-batch-remote',
      sourceRefs: [traceableRef(snippet: 'Remote conflict evidence.')],
    ).copyWith(
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    await cardStore.stageRemoteSyncConflict(
      KnowledgeSyncEnvelope(
        id: remoteConflictCard.id,
        entityType: KnowledgeSyncEntityType.knowledgeCard,
        schemaVersion: 1,
        updatedAt: 300,
        conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
        conflictReason: 'content-conflict',
        sourceRefs: remoteConflictCard.sourceRefs,
        payload: remoteConflictCard.toJson(),
      ),
    );

    final retryRun = await controller.applyApprovedSyncConflicts();
    final missingAfterRetry = await reviewStore.getById(missingRemoteItem.id);

    expect(retryRun.appliedIds, [missingRemoteItem.id]);
    expect(retryRun.failed, isEmpty);
    expect(missingAfterRetry?.status, ReviewItemStatus.applied);
    expect(
      await cardStore.getStagedRemoteSyncConflictById('kc-batch-remote'),
      isNull,
    );
  });

  test('staged remote sync conflict fails closed without staged envelope',
      () async {
    final item = ReviewItem(
      id: 'sync-conflict-remote-staged:kc-missing-stage',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'kc-missing-stage',
      title: 'Sync conflict: kc-missing-stage',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      payload: const {
        'canApply': true,
        'remoteStaged': true,
        'stagedConflictId': 'kc-missing-stage',
      },
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);
    await controller.approve(item.id);

    await expectLater(
      controller.apply(item.id),
      throwsA(isA<StateError>()),
    );

    final unchanged = await reviewStore.getById(item.id);
    expect(unchanged?.status, ReviewItemStatus.approved);
    expect(unchanged?.appliedAt, isNull);
    expect(await cardStore.getById(item.sourceId), isNull);
  });

  test('staged remote sync conflict rejects mismatched staged envelope',
      () async {
    final stagedRemoteCard = card(id: 'kc-other-staged').copyWith(
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    await cardStore.stageRemoteSyncConflict(
      KnowledgeSyncEnvelope(
        id: stagedRemoteCard.id,
        entityType: KnowledgeSyncEntityType.knowledgeCard,
        schemaVersion: 1,
        updatedAt: 200,
        conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
        conflictReason: 'content-conflict',
        sourceRefs: stagedRemoteCard.sourceRefs,
        payload: stagedRemoteCard.toJson(),
      ),
    );
    final item = ReviewItem(
      id: 'sync-conflict-remote-staged:kc-forged-source',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'kc-forged-source',
      title: 'Sync conflict: kc-forged-source',
      body: 'Conflict reason: content-conflict',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      payload: const {
        'canApply': true,
        'remoteStaged': true,
        'stagedConflictId': 'kc-other-staged',
      },
      createdAt: 100,
      updatedAt: 100,
    );
    await reviewStore.upsert(item);
    await controller.approve(item.id);

    await expectLater(
      controller.apply(item.id),
      throwsA(isA<StateError>()),
    );

    final unchanged = await reviewStore.getById(item.id);
    expect(unchanged?.status, ReviewItemStatus.approved);
    expect(unchanged?.appliedAt, isNull);
    expect(await cardStore.getById(item.sourceId), isNull);
    expect(
      await cardStore.getStagedRemoteSyncConflictById('kc-other-staged'),
      isNotNull,
    );
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
