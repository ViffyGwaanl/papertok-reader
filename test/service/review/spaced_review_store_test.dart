import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

void main() {
  late Directory tempRoot;
  late SpacedReviewStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('spaced_review_store_');
    store = SpacedReviewStore(rootDir: tempRoot);
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 9,
    String cfi = 'epubcfi(/6/12)',
    String snippet = 'Traceable evidence.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: 'Text/chapter.xhtml',
        cfi: cfi,
        jumpLink: 'paperreader://reader/open?bookId=$bookId&cfi=$cfi',
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard appliedCard({
    String id = 'kc-spaced',
    List<SourceRef>? sourceRefs,
  }) =>
      KnowledgeCard(
        id: id,
        title: 'Attention bottleneck',
        quote: 'Traceable evidence.',
        explanation: 'The reader should revisit this card later.',
        sourceRefs: sourceRefs ?? [traceableRef()],
        reviewState: KnowledgeCardReviewState.applied,
        ownership: AiOutputOwnership.aiGeneratedApproved,
        createdAt: 100,
        updatedAt: 100,
      );

  test('upsert from applied knowledge card creates one due review item',
      () async {
    final first = await store.upsertFromKnowledgeCard(
      appliedCard(),
      now: 1000,
    );
    final duplicate = await store.upsertFromKnowledgeCard(
      appliedCard(),
      now: 2000,
    );
    final allItems = await store.list();
    final dueItems = await store.list(dueOnly: true, now: 1000);

    expect(first.id, SpacedReviewStore.reviewIdForCard('kc-spaced'));
    expect(first.cardId, 'kc-spaced');
    expect(first.dueAt, 1000);
    expect(duplicate.id, first.id);
    expect(allItems, hasLength(1));
    expect(dueItems.single.id, first.id);
    expect(dueItems.single.sourceRefs.single.hasEvidence, true);
  });

  test('record review updates due date, interval, and history', () async {
    final item = await store.upsertFromKnowledgeCard(
      appliedCard(),
      now: 1000,
    );

    final reviewed = await store.recordReview(
      item.id,
      rating: SpacedReviewRating.good,
      now: 1000,
    );
    final dueNow = await store.list(dueOnly: true, now: 1000);
    final dueLater = await store.list(
      dueOnly: true,
      now: 1000 + Duration.millisecondsPerDay * 3,
    );

    expect(reviewed.lastReviewedAt, 1000);
    expect(reviewed.intervalDays, 3);
    expect(reviewed.dueAt, 1000 + Duration.millisecondsPerDay * 3);
    expect(reviewed.reviewHistory.single.rating, 'good');
    expect(dueNow, isEmpty);
    expect(dueLater.single.id, item.id);
  });

  test('again rating increments lapses and keeps source provenance', () async {
    final item = await store.upsertFromKnowledgeCard(
      appliedCard(),
      now: 1000,
    );

    final reviewed = await store.recordReview(
      item.id,
      rating: SpacedReviewRating.again,
      now: 1000,
    );
    final audit = store.sourceJumpAudit(reviewed);

    expect(reviewed.intervalDays, 1);
    expect(reviewed.lapses, 1);
    expect(reviewed.sourceRefs.single.sourceTextSnippet, 'Traceable evidence.');
    expect(audit.jumpableCount, 1);
    expect(audit.unavailableCount, 0);
  });

  test('rejects cards that are not applied traceable user assets', () async {
    final pending = appliedCard().copyWith(
      reviewState: KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
    final approved = appliedCard().copyWith(
      reviewState: KnowledgeCardReviewState.approved,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );

    expect(
      () => store.upsertFromKnowledgeCard(pending, now: 1000),
      throwsStateError,
    );
    expect(
      () => store.upsertFromKnowledgeCard(approved, now: 1000),
      throwsStateError,
    );
  });
}
