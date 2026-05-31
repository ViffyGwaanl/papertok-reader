import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late Directory tempRoot;
  late ReviewItemStore reviewStore;
  late KnowledgeCardStore cardStore;
  late ReviewInboxController controller;
  late ProviderContainer container;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('review_inbox_provider_');
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    controller = ReviewInboxController(
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      now: () => 2000,
    );
    container = ProviderContainer(
      overrides: [
        reviewInboxControllerProvider.overrideWithValue(controller),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef() => SourceRef(
        bookId: 3,
        href: 'Text/chapter.xhtml',
        cfi: 'epubcfi(/6/10)',
        sourceTextSnippet: 'A traceable review passage.',
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({required String id}) => KnowledgeCard(
        id: id,
        title: 'Card $id',
        quote: 'A traceable review passage.',
        explanation: 'Review inbox provider should refresh after actions.',
        sourceRefs: [traceableRef()],
        reviewState: KnowledgeCardReviewState.pending,
        ownership: AiOutputOwnership.aiGeneratedDraft,
      );

  Future<void> stageKnowledgeCard(String id) async {
    final staged = await cardStore.upsertCandidate(card(id: id));
    await reviewStore.upsert(
      KnowledgeCardReviewAdapter.fromKnowledgeCard(staged.card),
    );
  }

  test('refresh lists pending review items by default', () async {
    await stageKnowledgeCard('kc-provider');

    await container.read(reviewInboxProvider.notifier).refresh();
    final state = container.read(reviewInboxProvider);

    expect(state.statusFilter, ReviewItemStatus.pending);
    expect(state.items.value!.map((item) => item.id), [
      'knowledge-card:kc-provider',
    ]);
    expect(state.isBusy('knowledge-card:kc-provider'), false);
  });

  test('approve action refreshes filtered inbox', () async {
    await stageKnowledgeCard('kc-approve');
    final notifier = container.read(reviewInboxProvider.notifier);

    await notifier.refresh();
    await notifier.approve('knowledge-card:kc-approve');

    expect(
      container.read(reviewInboxProvider).items.value,
      isEmpty,
      reason: 'default pending filter should no longer show approved items',
    );

    await notifier.setStatusFilter(ReviewItemStatus.approved);
    final approvedItems = container.read(reviewInboxProvider).items.value!;
    final approvedCard = await cardStore.getById('kc-approve');

    expect(approvedItems.single.id, 'knowledge-card:kc-approve');
    expect(approvedItems.single.status, ReviewItemStatus.approved);
    expect(approvedCard!.reviewState, KnowledgeCardReviewState.approved);
  });

  test('batch apply approved safe sync conflicts keeps failures retryable',
      () async {
    final controller = _BatchReviewInboxController();
    final container = ProviderContainer(
      overrides: [
        reviewInboxControllerProvider.overrideWithValue(controller),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(reviewInboxProvider.notifier);

    await notifier.setStatusFilter(ReviewItemStatus.approved);
    await notifier.setSourceTypeFilter(ReviewItemSourceType.syncConflict);
    await notifier.applyApprovedSyncConflicts();
    final state = container.read(reviewInboxProvider);

    expect(controller.batchRuns, 1);
    expect(controller.appliedIds, ['sync-conflict:ready']);
    expect(state.items.value!.map((item) => item.id), [
      'sync-conflict:retry',
      'sync-conflict:preview',
      'sync-conflict:unavailable',
    ]);
    expect(state.items.value!.first.status, ReviewItemStatus.approved);
    expect(state.lastError, contains('1 sync conflict failed'));
    expect(state.isApplyingBatchSyncConflicts, false);

    await notifier.applyApprovedSyncConflicts();

    expect(controller.batchRuns, 2);
    expect(controller.appliedIds, [
      'sync-conflict:ready',
      'sync-conflict:retry',
    ]);
    expect(
        container.read(reviewInboxProvider).items.value!.map((item) => item.id),
        [
          'sync-conflict:preview',
          'sync-conflict:unavailable',
        ]);
  });

  test('batch apply waits for approved sync conflict filter', () async {
    final controller = _BatchReviewInboxController();
    final container = ProviderContainer(
      overrides: [
        reviewInboxControllerProvider.overrideWithValue(controller),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(reviewInboxProvider.notifier);

    await notifier.setStatusFilter(ReviewItemStatus.approved);
    final state = container.read(reviewInboxProvider);

    expect(state.canApplyApprovedSyncConflicts, false);
    await notifier.applyApprovedSyncConflicts();
    expect(controller.batchRuns, 0);
  });
}

class _BatchReviewInboxController extends ReviewInboxController {
  final appliedIds = <String>[];
  var batchRuns = 0;
  var _retryCanApply = false;

  final _items = <String, ReviewItem>{
    'sync-conflict:ready': ReviewItem(
      id: 'sync-conflict:ready',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'ready',
      title: 'Sync conflict: ready',
      body: 'Safe conflict',
      status: ReviewItemStatus.approved,
      sourceRefs: [_traceableRef()],
      payload: const {'canApply': true},
    ),
    'sync-conflict:retry': ReviewItem(
      id: 'sync-conflict:retry',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'retry',
      title: 'Sync conflict: retry',
      body: 'Safe conflict that fails once',
      status: ReviewItemStatus.approved,
      sourceRefs: [_traceableRef()],
      payload: const {'canApply': true},
    ),
    'sync-conflict:preview': ReviewItem(
      id: 'sync-conflict:preview',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'preview',
      title: 'Sync conflict: preview',
      body: 'Preview-only conflict',
      status: ReviewItemStatus.approved,
      sourceRefs: [_traceableRef()],
      payload: const {'canApply': false, 'remotePreviewOnly': true},
    ),
    'sync-conflict:unavailable': ReviewItem(
      id: 'sync-conflict:unavailable',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: 'unavailable',
      title: 'Sync conflict: unavailable',
      body: 'Unavailable-only conflict',
      status: ReviewItemStatus.approved,
      sourceRefs: [
        SourceRef(
          sourceKind: SourceRefKind.unknown,
          unavailableReason: 'sync-conflict-no-source',
        ),
      ],
      payload: const {'canApply': true},
    ),
  };

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return _items.values.where((item) {
      if (status != null && item.status != status) return false;
      if (sourceType != null && item.sourceType != sourceType) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<ReviewInboxBatchApplyResult> applyApprovedSyncConflicts() async {
    batchRuns += 1;
    final failures = <ReviewInboxBatchApplyFailure>[];
    final applied = <ReviewItem>[];
    for (final item in _items.values.toList(growable: false)) {
      if (!ReviewInboxController.canBatchApplySyncConflict(item)) {
        continue;
      }
      if (item.id == 'sync-conflict:retry' && !_retryCanApply) {
        _retryCanApply = true;
        failures.add(
          ReviewInboxBatchApplyFailure(
            id: item.id,
            error: 'temporary failure',
          ),
        );
        continue;
      }
      appliedIds.add(item.id);
      final appliedItem = item.copyWith(status: ReviewItemStatus.applied);
      _items[item.id] = appliedItem;
      applied.add(appliedItem);
    }
    return ReviewInboxBatchApplyResult(applied: applied, failed: failures);
  }
}

SourceRef _traceableRef() => SourceRef(
      bookId: 3,
      href: 'Text/chapter.xhtml',
      cfi: 'epubcfi(/6/10)',
      sourceTextSnippet: 'A traceable review passage.',
      sourceKind: SourceRefKind.highlight,
    );
