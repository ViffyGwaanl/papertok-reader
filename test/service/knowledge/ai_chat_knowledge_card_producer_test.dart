import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/ai_chat_knowledge_card_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late ReviewItemStore reviewStore;
  late AiChatKnowledgeCardProducer producer;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ai-chat-card-');
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    producer = AiChatKnowledgeCardProducer(
      cardStore: cardStore,
      reviewStore: reviewStore,
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('assistant answer becomes pending KnowledgeCard review item', () async {
    final result = await producer.createFromAssistantAnswer(
      assistantAnswer: 'Attention is a mechanism for weighting context.',
      userPrompt: 'Explain attention.',
      conversationId: 'chat-1',
      messageNodeId: 'assistant:1',
      modelId: 'gpt-test',
      bookId: 7,
      bookTitle: 'Transformer Notes',
      cfi: 'epubcfi(/6/4)',
      chapterTitle: 'Chapter 2',
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, true);
    expect(result.card.origin, KnowledgeCardOrigin.aiChat);
    expect(result.card.reviewState, KnowledgeCardReviewState.pending);
    expect(result.card.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(result.card.quote, 'Explain attention.');
    expect(result.card.explanation, contains('Attention is a mechanism'));
    expect(result.card.tags, contains('ai-chat'));
    expect(result.card.sourceRefs, hasLength(2));
    expect(result.card.sourceRefs.first.sourceKind, SourceRefKind.conversation);
    expect(result.card.sourceRefs.first.modelId, 'gpt-test');
    expect(result.card.sourceRefs.first.hasUnavailableReason, true);
    expect(result.card.sourceRefs.last.canJumpBack, true);

    final reviewItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, result.card.id);
    expect(reviewItems.single.sourceRefs.first.sourceKind,
        SourceRefKind.conversation);
  });

  test('assistant answer preserves exact selected reader SourceRef', () async {
    final exactSelectionRef = SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/4[exact-selection])',
      jumpLink:
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28%2F6%2F4%5Bexact-selection%5D%29',
      sourceTitle: 'Transformer Notes',
      locationLabel: 'Chapter 2',
      sourceTextSnippet: 'Exact selected passage.',
      sourceTextForHash: 'Exact selected passage.',
      sourceKind: SourceRefKind.reader,
      createdAt: 90,
    );

    final result = await producer.createFromAssistantAnswer(
      assistantAnswer: 'Attention is a mechanism for weighting context.',
      userPrompt: 'Exact selected passage.',
      conversationId: 'chat-selection',
      messageNodeId: 'assistant:1',
      modelId: 'gpt-test',
      bookId: 7,
      bookTitle: 'Transformer Notes',
      cfi: 'epubcfi(/6/4)',
      chapterTitle: 'Chapter 2',
      readerSourceRef: exactSelectionRef,
      now: 100,
    );

    expect(result.card.sourceRefs, hasLength(2));
    final readerRef = result.card.sourceRefs.last;
    expect(readerRef.sourceKind, SourceRefKind.reader);
    expect(readerRef.bookId, 7);
    expect(readerRef.cfi, 'epubcfi(/6/4[exact-selection])');
    expect(readerRef.sourceTextSnippet, 'Exact selected passage.');
    expect(readerRef.canJumpBack, true);
  });

  test('assistant answer derives conservative concept refs for review',
      () async {
    final result = await producer.createFromAssistantAnswer(
      assistantAnswer:
          'Attention is a mechanism for weighting context. SourceRef keeps the evidence jumpable.',
      userPrompt: 'Explain attention and SourceRef.',
      conversationId: 'chat-concepts',
      messageNodeId: 'assistant:1',
      bookId: 7,
      cfi: 'epubcfi(/6/4)',
      now: 100,
    );

    expect(result.card.conceptRefs, contains('Attention'));
    expect(result.card.conceptRefs, contains('SourceRef'));
    expect(result.card.conceptRefs.length, lessThanOrEqualTo(3));
    expect(result.reviewItem!.payload['card'], isA<Map<String, dynamic>>());
    final payload = result.reviewItem!.payload['card'] as Map<String, dynamic>;
    expect(payload['conceptRefs'], contains('Attention'));
  });

  test('applied AI chat card seeds draft ConceptGraph candidates after review',
      () async {
    final graphStore = ConceptGraphStore(rootDir: tempRoot);
    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      conceptGraphStore: graphStore,
      now: () => 200,
    );
    final result = await producer.createFromAssistantAnswer(
      assistantAnswer: 'Attention is a mechanism for weighting context.',
      userPrompt: 'Explain attention.',
      conversationId: 'chat-graph',
      messageNodeId: 'assistant:1',
      bookId: 7,
      cfi: 'epubcfi(/6/4)',
      now: 100,
    );

    await controller.approve(result.reviewItem!.id);
    await controller.apply(result.reviewItem!.id);

    final nodes = await graphStore.listNodes();
    final edges = await graphStore.listEdges();
    final relationReviews = await reviewStore.list(
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );

    expect(nodes.map((node) => node.id),
        contains(stableCardNodeId(result.card.id)));
    expect(nodes.map((node) => node.id), contains('concept:attention'));
    expect(edges, hasLength(1));
    expect(edges.single.isFormal, false);
    expect(relationReviews, hasLength(1));
    expect(relationReviews.single.status, ReviewItemStatus.pending);
  });

  test('pure chat answer still carries explainable conversation provenance',
      () async {
    final result = await producer.createFromAssistantAnswer(
      assistantAnswer: 'This is a reusable study insight.',
      userPrompt: 'What should I remember?',
      conversationId: 'chat-2',
      messageNodeId: 'assistant:1',
      now: 100,
    );

    expect(result.card.sourceRefs, hasLength(1));
    expect(
        result.card.sourceRefs.single.sourceKind, SourceRefKind.conversation);
    expect(result.card.sourceRefs.single.hasEvidence, true);
    expect(result.card.sourceRefs.single.canJumpBack, false);
    expect(result.card.sourceRefs.single.hasUnavailableReason, true);
    expect(result.card.conceptRefs, isEmpty);
  });

  test('duplicate chat answer does not create duplicate cards', () async {
    final first = await producer.createFromAssistantAnswer(
      assistantAnswer: 'Duplicate insight.',
      userPrompt: 'Explain it.',
      conversationId: 'chat-3',
      messageNodeId: 'assistant:1',
      now: 100,
    );
    final second = await producer.createFromAssistantAnswer(
      assistantAnswer: 'Duplicate insight.',
      userPrompt: 'Explain it.',
      conversationId: 'chat-3',
      messageNodeId: 'assistant:1',
      now: 200,
    );

    expect(first.inserted, true);
    expect(second.inserted, false);
    expect(second.duplicateOfId, first.card.id);
    expect(
        await cardStore.list(origin: KnowledgeCardOrigin.aiChat), hasLength(1));
  });

  test('blank assistant answer is rejected before writing stores', () async {
    await expectLater(
      producer.createFromAssistantAnswer(
        assistantAnswer: '   ',
        userPrompt: 'Explain it.',
        conversationId: 'chat-4',
        messageNodeId: 'assistant:1',
        now: 100,
      ),
      throwsArgumentError,
    );

    expect(await cardStore.list(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('long assistant answer is clipped before card and review persistence',
      () async {
    final longAnswer = List.filled(900, 'answer').join(' ');

    final result = await producer.createFromAssistantAnswer(
      assistantAnswer: longAnswer,
      userPrompt: 'Summarize.',
      conversationId: 'chat-5',
      messageNodeId: 'assistant:1',
      now: 100,
    );

    expect(result.card.explanation.length,
        lessThanOrEqualTo(AiChatKnowledgeCardProducer.maxAnswerChars));
    expect(result.card.sourceRefs.first.sourceTextSnippet!.length,
        lessThanOrEqualTo(SourceRef.maxSnippetChars));
    final payload = result.reviewItem!.payload['card'] as Map<String, dynamic>;
    expect((payload['explanation'] as String).length,
        lessThanOrEqualTo(AiChatKnowledgeCardProducer.maxAnswerChars));
  });
}

String stableCardNodeId(String cardId) {
  final normalized = cardId
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'card:$normalized';
}
