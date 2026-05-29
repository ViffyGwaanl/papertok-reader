import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/knowledge/ai_chat_knowledge_card_producer.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant answer Card action passes reading provenance',
      (tester) async {
    const providerId = 'openai';
    final fakeProducer = _FakeAiChatKnowledgeCardProducer();
    final providers = [
      AiProviderMeta(
        id: providerId,
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'selectedAiService': providerId,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
    });

    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiChatStream(
            chatKnowledgeCardProducer: fakeProducer,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    AnxToast.init(tester.element(find.byType(AiChatStream)));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream)),
    );
    await container.read(aiChatProvider.future);
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: Book.mock().copyWith(id: 7, title: 'Scoped Book'),
            cfi: 'epubcfi(/6/4)',
            chapterTitle: 'Chapter 1',
          ),
        );
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('Explain attention.'),
        ChatMessage.ai('Attention weights context for the current passage.'),
      ],
      sessionId: 'chat-ui-1',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('知识卡'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.assistantAnswer,
        'Attention weights context for the current passage.');
    expect(fakeProducer.calls.single.userPrompt, 'Explain attention.');
    expect(fakeProducer.calls.single.conversationId, 'chat-ui-1');
    expect(fakeProducer.calls.single.messageNodeId, 'assistant:1');
    expect(fakeProducer.calls.single.modelId, 'gpt-test');
    expect(fakeProducer.calls.single.bookId, 7);
    expect(fakeProducer.calls.single.bookTitle, 'Scoped Book');
    expect(fakeProducer.calls.single.cfi, 'epubcfi(/6/4)');
    expect(fakeProducer.calls.single.chapterTitle, 'Chapter 1');
  });

  testWidgets('assistant Card action forwards prefilled selection SourceRef',
      (tester) async {
    const providerId = 'openai';
    final fakeProducer = _FakeAiChatKnowledgeCardProducer();
    final chatKey = GlobalKey<AiChatStreamState>();
    final providers = [
      AiProviderMeta(
        id: providerId,
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];
    final selectionRef = SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/4[selection])',
      jumpLink:
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28%2F6%2F4%5Bselection%5D%29',
      sourceTitle: 'Scoped Book',
      locationLabel: 'Chapter 1',
      sourceTextSnippet: 'Attention needs exact evidence.',
      sourceTextForHash: 'Attention needs exact evidence.',
      sourceKind: SourceRefKind.reader,
      createdAt: 1,
    );

    SharedPreferences.setMockInitialValues({
      'selectedAiService': providerId,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_$providerId': jsonEncode({}),
    });

    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiChatStream(
            key: chatKey,
            chatKnowledgeCardProducer: fakeProducer,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    AnxToast.init(tester.element(find.byType(AiChatStream)));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream)),
    );
    await container.read(aiChatProvider.future);
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: Book.mock().copyWith(id: 7, title: 'Scoped Book'),
            cfi: 'epubcfi(/6/4)',
            chapterTitle: 'Chapter 1',
          ),
        );

    chatKey.currentState!.prefillDraft(
      message: 'Attention needs exact evidence.',
      sourceRef: selectionRef,
    );
    chatKey.currentState!.sendCurrentDraft();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('知识卡'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.userPrompt,
        'Attention needs exact evidence.');
    expect(fakeProducer.calls.single.readerSourceRef, isNotNull);
    expect(fakeProducer.calls.single.readerSourceRef!.cfi,
        'epubcfi(/6/4[selection])');
    expect(fakeProducer.calls.single.readerSourceRef!.sourceTextSnippet,
        'Attention needs exact evidence.');
  });
}

class _FakeAiChatKnowledgeCardProducer extends AiChatKnowledgeCardProducer {
  _FakeAiChatKnowledgeCardProducer();

  final calls = <_AiChatCardCall>[];

  @override
  Future<AiChatKnowledgeCardProducerResult> createFromAssistantAnswer({
    required String assistantAnswer,
    String? userPrompt,
    String? conversationId,
    String? messageNodeId,
    String? modelId,
    int? bookId,
    String? bookTitle,
    String? cfi,
    String? chapterTitle,
    SourceRef? readerSourceRef,
    int? now,
  }) async {
    calls.add(
      _AiChatCardCall(
        assistantAnswer: assistantAnswer,
        userPrompt: userPrompt,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        modelId: modelId,
        bookId: bookId,
        bookTitle: bookTitle,
        cfi: cfi,
        chapterTitle: chapterTitle,
        readerSourceRef: readerSourceRef,
      ),
    );
    final sourceRef = SourceRef(
      bookId: bookId,
      cfi: cfi,
      sourceTextSnippet: assistantAnswer,
      sourceKind: SourceRefKind.conversation,
      unavailableReason: 'fake',
    );
    final card = KnowledgeCard(
      id: 'fake-ai-chat-card',
      title: 'Fake',
      quote: userPrompt ?? '',
      explanation: assistantAnswer,
      sourceRefs: [sourceRef],
      reviewState: KnowledgeCardReviewState.pending,
      origin: KnowledgeCardOrigin.aiChat,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: 1,
      updatedAt: 1,
    );
    return AiChatKnowledgeCardProducerResult(
      card: card,
      inserted: true,
      addedToReviewInbox: true,
      reviewItem: ReviewItem(
        id: 'review:fake-ai-chat-card',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: card.id,
        title: card.title,
        body: card.explanation,
        status: ReviewItemStatus.pending,
        sourceRefs: card.sourceRefs,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  }
}

class _AiChatCardCall {
  const _AiChatCardCall({
    required this.assistantAnswer,
    this.userPrompt,
    this.conversationId,
    this.messageNodeId,
    this.modelId,
    this.bookId,
    this.bookTitle,
    this.cfi,
    this.chapterTitle,
    this.readerSourceRef,
  });

  final String assistantAnswer;
  final String? userPrompt;
  final String? conversationId;
  final String? messageNodeId;
  final String? modelId;
  final int? bookId;
  final String? bookTitle;
  final String? cfi;
  final String? chapterTitle;
  final SourceRef? readerSourceRef;
}
