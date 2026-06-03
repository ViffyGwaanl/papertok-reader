import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/knowledge/selection_knowledge_card_producer.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late ReviewItemStore reviewStore;
  late SelectionKnowledgeCardProducer producer;

  setUp(() async {
    tempRoot =
        await Directory.systemTemp.createTemp('selection_card_producer_');
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    producer = SelectionKnowledgeCardProducer(
      cardStore: cardStore,
      reviewStore: reviewStore,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('selected reader text defaults to a draft KnowledgeCard without Review',
      () async {
    final result = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, false);
    expect(result.reviewItem, isNull);
    expect(result.card.origin, KnowledgeCardOrigin.selection);
    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(result.card.quote, 'Argument mapping helps readers compare claims.');
    expect(result.card.sourceRefs.single.bookId, 42);
    expect(result.card.sourceRefs.single.cfi, 'epubcfi(/6/4)');
    expect(result.card.sourceRefs.single.canJumpBack, true);

    final cards = await cardStore.list();
    expect(cards, hasLength(1));
    expect(cards.single.id, result.card.id);
    expect(await reviewStore.list(), isEmpty);
  });

  test('selected reader text can be explicitly sent to Review', () async {
    final result = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      createReviewItem: true,
      now: 100,
    );

    final reviewItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, true);
    expect(result.card.reviewState, KnowledgeCardReviewState.pending);
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, result.card.id);
    expect(reviewItems.single.sourceRefs.single.canJumpBack, true);
  });

  test('selected reader text can be saved as draft without Review', () async {
    final result = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, false);
    expect(result.reviewItem, isNull);
    expect(result.card.origin, KnowledgeCardOrigin.selection);
    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(
        result.card.explanation, contains('Selected passage saved as draft'));
    expect(result.card.explanation, isNot(contains('review')));
    expect(result.card.sourceRefs.single.canJumpBack, true);

    final cards = await cardStore.list(
      reviewState: KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.selection,
    );
    expect(cards, hasLength(1));
    expect(await reviewStore.list(), isEmpty);
  });

  test('duplicate selected text reuses existing card without duplicate inbox',
      () async {
    final first = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      now: 100,
    );
    final second = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: ' Argument   mapping helps readers compare claims. ',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      now: 200,
    );

    expect(second.inserted, false);
    expect(second.duplicateOfId, first.card.id);
    expect(second.addedToReviewInbox, false);
    expect(second.reviewItem, isNull);
    expect(await cardStore.list(), hasLength(1));
    expect(await reviewStore.list(), isEmpty);
  });

  test('duplicate approved card is not re-added to pending review', () async {
    final first = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      createReviewItem: true,
      now: 100,
    );
    final approvedReviewItem = await reviewStore.approve(
      first.reviewItem!.id,
      now: 150,
    );
    await cardStore.applyReviewDecision(approvedReviewItem, now: 150);

    final second = await producer.createFromSelection(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      selectedText: 'Argument mapping helps readers compare claims.',
      chapterTitle: 'Chapter 2',
      bookTitle: 'Thinking With Books',
      createReviewItem: true,
      now: 200,
    );

    expect(second.inserted, false);
    expect(second.duplicateOfId, first.card.id);
    expect(second.addedToReviewInbox, false);
    expect(
      await reviewStore.list(
        status: ReviewItemStatus.pending,
        sourceType: ReviewItemSourceType.knowledgeCard,
      ),
      isEmpty,
    );
    expect(
      await reviewStore.list(
        status: ReviewItemStatus.approved,
        sourceType: ReviewItemSourceType.knowledgeCard,
      ),
      hasLength(1),
    );
  });

  test('blank selection is rejected before writing stores', () async {
    expect(
      () => producer.createFromSelection(
        bookId: 42,
        cfi: 'epubcfi(/6/4)',
        selectedText: '   ',
      ),
      throwsArgumentError,
    );

    expect(await cardStore.list(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });
}
