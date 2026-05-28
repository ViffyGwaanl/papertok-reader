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
}
