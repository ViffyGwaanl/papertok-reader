import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late SpacedReviewStore spacedReviewStore;
  late ProviderContainer container;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('spaced_review_provider_');
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    container = ProviderContainer(
      overrides: [
        spacedReviewKnowledgeCardStoreProvider.overrideWithValue(cardStore),
        spacedReviewStoreProvider.overrideWithValue(spacedReviewStore),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef() => SourceRef(
        bookId: 5,
        cfi: 'epubcfi(/6/10)',
        jumpLink: 'paperreader://reader/open?bookId=5&cfi=epubcfi%28/6/10%29',
        sourceTextSnippet: 'Traceable recovery evidence.',
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({required String id}) => KnowledgeCard(
        id: id,
        title: 'Recovered card',
        quote: 'Traceable recovery evidence.',
        explanation: 'Applied cards should be recoverable into review.',
        sourceRefs: [traceableRef()],
        reviewState: KnowledgeCardReviewState.pending,
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: 100,
        updatedAt: 100,
      );

  Future<void> stageAppliedCard(String id) async {
    final staged = await cardStore.upsertCandidate(card(id: id));
    final pending = KnowledgeCardReviewAdapter.fromKnowledgeCard(staged.card);
    final approved = pending.transitionTo(
      ReviewItemStatus.approved,
      now: 200,
      decisionSource: 'user_approve',
    );
    final applied = approved.transitionTo(
      ReviewItemStatus.applied,
      now: 300,
      decisionSource: 'user_apply',
    );
    await cardStore.applyReviewDecision(approved, now: 200);
    await cardStore.applyReviewDecision(applied, now: 300);
  }

  test('refresh reconciles applied knowledge cards into review queue',
      () async {
    await stageAppliedCard('kc-recover');

    await container.read(spacedReviewProvider.notifier).refresh();
    final state = container.read(spacedReviewProvider);

    expect(state.items.value, hasLength(1));
    expect(
      state.items.value!.single.id,
      SpacedReviewStore.reviewIdForCard('kc-recover'),
    );
    expect(state.items.value!.single.sourceRefs.single.hasEvidence, true);
  });
}
