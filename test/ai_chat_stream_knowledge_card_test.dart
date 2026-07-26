import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
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

    await tester.tap(find.widgetWithText(TextButton, '知识卡').last);
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
    expect(fakeProducer.calls.single.readerSourceRef, isNull);
  });

  testWidgets('assistant Card action saves draft inline without Review',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: Scaffold(
            body: AiChatStream(
              chatKnowledgeCardProducer: fakeProducer,
            ),
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
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('Explain attention.'),
        ChatMessage.ai('Attention weights context for the current passage.'),
      ],
      sessionId: 'chat-ui-draft-card',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(TextButton, '知识卡').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.createReviewItem, false);
    expect(find.text('已保存为草稿知识卡'), findsOneWidget);
    expect(find.text('查看知识卡'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('查看知识卡'));
    await tester.pumpAndSettle();

    expect(find.text('知识卡详情'), findsOneWidget);
    expect(find.text('Fake'), findsOneWidget);
    expect(
      find.text('Attention weights context for the current passage.'),
      findsWidgets,
    );
  });

  testWidgets('assistant Card action is disabled while streaming',
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
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('Explain active reading.'),
        ChatMessage.ai('The answer is still streaming.'),
      ],
      sessionId: 'chat-streaming-card-gate',
    );
    container.read(aiChatStreamingProvider.notifier).setStreaming(true);
    await tester.pump(const Duration(milliseconds: 100));

    final cardButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '知识卡'),
    );
    expect(cardButton.onPressed, isNull);

    await tester.tap(find.text('知识卡'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeProducer.calls, isEmpty);
  });

  testWidgets('assistant Card action forwards prefilled selection SourceRef',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-card-source-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

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
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2100));

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

    await tester.runAsync(() async {
      container
          .read(aiChatProvider.notifier)
          .persistCurrentConversationWithContainer(container);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final history = await AiHistoryStore.readHistory();
      final sourceRefs = history.expand((entry) {
        final nodes = entry.conversationV2?['nodes'];
        if (nodes is! Map) return const <Map<String, dynamic>>[];
        return nodes.values
            .whereType<Map>()
            .map((node) => node['sourceRef'])
            .whereType<Map>()
            .map((ref) => ref.map((k, v) => MapEntry(k.toString(), v)));
      }).toList(growable: false);

      expect(sourceRefs.map((ref) => ref['cfi']),
          contains('epubcfi(/6/4[selection])'));
    });
  });

  testWidgets('unrelated draft rewrite does not persist selection SourceRef',
      (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-card-rewrite-source-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    const providerId = 'openai';
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
    chatKey.currentState!.inputController.text =
        'What should I remember about this project?';
    chatKey.currentState!.sendCurrentDraft();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(find.textContaining('What should I remember'), findsWidgets);
    final messages = container.read(aiChatProvider).asData!.value;
    final userIndex = messages.indexWhere(
      (message) =>
          message is HumanChatMessage &&
          message.contentAsString ==
              'What should I remember about this project?',
    );
    expect(userIndex, isNot(-1));
    expect(
      container
          .read(aiChatProvider.notifier)
          .sourceRefForMessageIndex(userIndex),
      isNull,
    );
  });

  testWidgets('short snippet coincidence does not persist selection SourceRef',
      (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-card-short-source-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    const providerId = 'openai';
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
      cfi: 'epubcfi(/6/4[short])',
      jumpLink:
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28%2F6%2F4%5Bshort%5D%29',
      sourceTitle: 'Scoped Book',
      locationLabel: 'Chapter 1',
      sourceTextSnippet: 'AI',
      sourceTextForHash: 'AI',
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

    chatKey.currentState!.prefillDraft(
      message: 'AI',
      sourceRef: selectionRef,
    );
    chatKey.currentState!.inputController.text =
        'What AI tools should I use for this project?';
    chatKey.currentState!.sendCurrentDraft();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2100));

    final messages = container.read(aiChatProvider).asData!.value;
    final userIndex = messages.indexWhere(
      (message) =>
          message is HumanChatMessage &&
          message.contentAsString ==
              'What AI tools should I use for this project?',
    );
    expect(userIndex, isNot(-1));
    expect(
      container
          .read(aiChatProvider.notifier)
          .sourceRefForMessageIndex(userIndex),
      isNull,
    );
  });

  testWidgets('assistant Card action restores persisted reader SourceRef',
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
    container.read(aiChatProvider.notifier).loadHistoryEntry(
          _entryWithPersistedReaderSourceRef(selectionRef),
        );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 个可跳转来源'), findsOneWidget);
    expect(find.byTooltip('可跳回原文'), findsOneWidget);
    await tester.tap(find.text('知识卡'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.conversationId, 'history-with-source-ref');
    expect(fakeProducer.calls.single.userPrompt,
        'Attention needs exact evidence.');
    expect(fakeProducer.calls.single.readerSourceRef, isNotNull);
    expect(fakeProducer.calls.single.readerSourceRef!.cfi,
        'epubcfi(/6/4[selection])');
    expect(fakeProducer.calls.single.readerSourceRef!.sourceTextSnippet,
        'Attention needs exact evidence.');
  });

  testWidgets(
      'loaded legacy history without SourceRef does not use current reader fallback',
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
            book: Book.mock().copyWith(id: 99, title: 'Currently Open Book'),
            cfi: 'epubcfi(/99/2)',
            chapterTitle: 'Wrong current chapter',
          ),
        );
    container.read(aiChatProvider.notifier).loadHistoryEntry(
          _legacyEntryWithoutPersistedReaderSourceRef(),
        );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 个已标记不可用'), findsOneWidget);
    expect(find.byTooltip('仅保留会话来源，不能跳回原文'), findsOneWidget);
    await tester.tap(find.text('知识卡'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.conversationId, 'legacy-history');
    expect(fakeProducer.calls.single.readerSourceRef, isNull);
    expect(fakeProducer.calls.single.bookId, isNull);
    expect(fakeProducer.calls.single.cfi, isNull);
  });

  testWidgets('current reading fallback without cfi is marked unavailable',
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
            book: Book.mock().copyWith(id: 7, title: 'No CFI Book'),
            chapterTitle: 'Chapter without location',
          ),
        );
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('Explain the current idea.'),
        ChatMessage.ai('The answer needs a real reader anchor.'),
      ],
      sessionId: 'chat-ui-no-cfi',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 个已标记不可用'), findsOneWidget);
    expect(find.byTooltip('仅保留会话来源，不能跳回原文'), findsOneWidget);
    await tester.tap(find.text('知识卡'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeProducer.calls, hasLength(1));
    expect(fakeProducer.calls.single.conversationId, 'chat-ui-no-cfi');
    expect(fakeProducer.calls.single.bookId, isNull);
    expect(fakeProducer.calls.single.cfi, isNull);
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
    bool createReviewItem = false,
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
        createReviewItem: createReviewItem,
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
      reviewState: createReviewItem
          ? KnowledgeCardReviewState.pending
          : KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.aiChat,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: 1,
      updatedAt: 1,
    );
    return AiChatKnowledgeCardProducerResult(
      card: card,
      inserted: true,
      addedToReviewInbox: createReviewItem,
      reviewItem: createReviewItem
          ? ReviewItem(
              id: 'review:fake-ai-chat-card',
              sourceType: ReviewItemSourceType.knowledgeCard,
              sourceId: card.id,
              title: card.title,
              body: card.explanation,
              status: ReviewItemStatus.pending,
              sourceRefs: card.sourceRefs,
              createdAt: 1,
              updatedAt: 1,
            )
          : null,
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
    required this.createReviewItem,
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
  final bool createReviewItem;
}

AiChatHistoryEntry _entryWithPersistedReaderSourceRef(SourceRef sourceRef) {
  return AiChatHistoryEntry(
    id: 'history-with-source-ref',
    serviceId: 'openai',
    model: 'gpt-test',
    createdAt: 1,
    updatedAt: 2,
    title: 'Attention',
    titleSource: 'manual',
    messages: [
      ChatMessage.humanText('Attention needs exact evidence.'),
      ChatMessage.ai('Attention weights context for the current passage.'),
    ],
    completed: true,
    bookId: 7,
    bookTitle: 'Scoped Book',
    conversationV2: {
      'schemaVersion': 2,
      'rootId': 'root',
      'nodes': {
        'root': {
          'parentId': null,
          'children': ['user-1'],
          'activeChildId': 'user-1',
          'message': null,
          'createdAt': 0,
          'updatedAt': 0,
        },
        'user-1': {
          'parentId': 'root',
          'children': ['assistant-1'],
          'activeChildId': 'assistant-1',
          'message':
              ChatMessage.humanText('Attention needs exact evidence.').toMap(),
          'sourceRef': sourceRef.toJson(),
          'createdAt': 1,
          'updatedAt': 1,
        },
        'assistant-1': {
          'parentId': 'user-1',
          'children': <String>[],
          'activeChildId': null,
          'message': ChatMessage.ai(
            'Attention weights context for the current passage.',
          ).toMap(),
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}

AiChatHistoryEntry _legacyEntryWithoutPersistedReaderSourceRef() {
  return AiChatHistoryEntry(
    id: 'legacy-history',
    serviceId: 'openai',
    model: 'gpt-test',
    createdAt: 1,
    updatedAt: 2,
    title: 'Legacy',
    titleSource: 'manual',
    messages: [
      ChatMessage.humanText('Legacy question.'),
      ChatMessage.ai('Legacy answer.'),
    ],
    completed: true,
    bookId: 7,
    bookTitle: 'Original Book',
    conversationV2: {
      'schemaVersion': 2,
      'rootId': 'root',
      'nodes': {
        'root': {
          'parentId': null,
          'children': ['user-1'],
          'activeChildId': 'user-1',
          'message': null,
          'createdAt': 0,
          'updatedAt': 0,
        },
        'user-1': {
          'parentId': 'root',
          'children': ['assistant-1'],
          'activeChildId': 'assistant-1',
          'message': ChatMessage.humanText('Legacy question.').toMap(),
          'createdAt': 1,
          'updatedAt': 1,
        },
        'assistant-1': {
          'parentId': 'user-1',
          'children': <String>[],
          'activeChildId': null,
          'message': ChatMessage.ai('Legacy answer.').toMap(),
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}

void _mockPathProvider(String? cachePath) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel,
          cachePath == null
              ? null
              : (call) async {
                  if (call.method == 'getApplicationCacheDirectory') {
                    return cachePath;
                  }
                  return cachePath;
                });
}
