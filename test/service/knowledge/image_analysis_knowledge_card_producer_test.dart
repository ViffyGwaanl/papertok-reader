import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/image_analysis_knowledge_card_producer.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late ReviewItemStore reviewStore;
  late ImageAnalysisKnowledgeCardProducer producer;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('image-card-producer-');
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    producer = ImageAnalysisKnowledgeCardProducer(
      cardStore: cardStore,
      reviewStore: reviewStore,
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('image analysis becomes a pending KnowledgeCard review item', () async {
    final result = await producer.createFromImageAnalysis(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      href: 'Text/chapter.xhtml',
      analysisText:
          'The figure compares retrieval paths and highlights evidence drift.',
      imageTitle: 'Retrieval diagram',
      imageAlt: 'Two retrieval paths',
      contextText: 'A figure about RAG evidence.',
      chapterTitle: 'Chapter 3',
      bookTitle: 'PaperTok Notes',
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, true);
    expect(result.card.origin, KnowledgeCardOrigin.imageAnalysis);
    expect(result.card.reviewState, KnowledgeCardReviewState.pending);
    expect(result.card.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(result.card.explanation, contains('evidence drift'));
    expect(result.card.quote, contains('A figure about RAG evidence'));
    expect(result.card.sourceRefs.single.bookId, 7);
    expect(result.card.sourceRefs.single.cfi, 'epubcfi(/6/8)');
    expect(result.card.sourceRefs.single.href, 'Text/chapter.xhtml');
    expect(result.card.sourceRefs.single.canJumpBack, true);
    expect(result.card.sourceRefs.single.sourceKind, SourceRefKind.reader);

    final reviewItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, result.card.id);
    expect(reviewItems.single.sourceRefs.single.canJumpBack, true);
  });

  test('duplicate image analysis does not create duplicate cards', () async {
    final first = await producer.createFromImageAnalysis(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      analysisText: 'The image explains a single evidence chain.',
      imageTitle: 'Evidence chain',
      contextText: 'A diagram about provenance.',
      now: 100,
    );

    final second = await producer.createFromImageAnalysis(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      analysisText: 'The image explains a single evidence chain.',
      imageTitle: 'Evidence chain',
      contextText: 'A diagram about provenance.',
      now: 200,
    );

    expect(first.inserted, true);
    expect(second.inserted, false);
    expect(second.duplicateOfId, first.card.id);

    final cards =
        await cardStore.list(origin: KnowledgeCardOrigin.imageAnalysis);
    expect(cards, hasLength(1));
  });

  test('image context is clipped before card and review payload persistence',
      () async {
    final longContext = List.filled(900, 'context').join(' ');

    final result = await producer.createFromImageAnalysis(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      analysisText: 'The image explains a compact idea.',
      imageTitle: 'Long context image',
      contextText: longContext,
      now: 100,
    );

    expect(
      result.card.quote.length,
      lessThanOrEqualTo(SourceRef.maxSnippetChars),
    );
    expect(
      result.card.sourceRefs.single.sourceTextSnippet!.length,
      lessThanOrEqualTo(SourceRef.maxSnippetChars),
    );

    final cardPayload =
        result.reviewItem!.payload['card'] as Map<String, dynamic>;
    expect(
      (cardPayload['quote'] as String).length,
      lessThanOrEqualTo(SourceRef.maxSnippetChars),
    );
  });

  test('blank image analysis is rejected before writing stores', () async {
    await expectLater(
      producer.createFromImageAnalysis(
        bookId: 7,
        cfi: 'epubcfi(/6/8)',
        analysisText: '   ',
        now: 100,
      ),
      throwsArgumentError,
    );

    expect(await cardStore.list(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });
}
