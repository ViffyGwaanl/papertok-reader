import 'dart:async';
import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().aiTitleGenerationEnabled = false;
    _configureAiProvider();
  });

  tearDown(() {
    debugAiChatGenerateStreamOverride = null;
  });

  test('beginFreshConversation clears current ai chat session state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('hello'),
        ChatMessage.ai('world'),
      ],
      sessionId: 'session-1',
    );

    expect(
        container.read(aiChatProvider.notifier).currentSessionId, 'session-1');
    expect(container.read(aiChatProvider).value, isNotEmpty);

    container
        .read(aiChatProvider.notifier)
        .beginFreshConversation(container, persistCurrent: false);

    expect(container.read(aiChatProvider.notifier).currentSessionId, isNull);
    expect(container.read(aiChatProvider).value, isEmpty);
  });

  test('persistCurrentConversation tags history with current reading book',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-provider-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    final book = Book.mock().copyWith(id: 7, title: 'Scoped Book');
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(book: book),
        );

    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('hello'),
        ChatMessage.ai('world'),
      ],
      sessionId: 'session-1',
    );

    container
        .read(aiChatProvider.notifier)
        .persistCurrentConversationWithContainer(container);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    expect(history.single.bookId, 7);
    expect(history.single.bookTitle, 'Scoped Book');
  });

  test('persistCurrentConversation does not backfill legacy history book scope',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-provider-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    final book = Book.mock().copyWith(id: 7, title: 'Scoped Book');
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(book: book),
        );

    final legacyEntry = AiChatHistoryEntry(
      id: 'legacy-session',
      serviceId: 'openai',
      model: 'gpt-test',
      createdAt: 1,
      updatedAt: 2,
      messages: [
        ChatMessage.humanText('legacy question'),
        ChatMessage.ai('legacy answer'),
      ],
      completed: true,
    );
    await container.read(aiHistoryProvider.notifier).upsert(legacyEntry);

    container.read(aiChatProvider.notifier).loadHistoryEntry(legacyEntry);
    container
        .read(aiChatProvider.notifier)
        .persistCurrentConversationWithContainer(container);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    expect(history.single.bookId, isNull);
    expect(history.single.bookTitle, isNull);
  });

  test('startStreaming coalesces rapid assistant chunk updates for scrolling',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-throttle-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    final visibleAssistantUpdates = <String>[];
    final subscription = container.listen<AsyncValue<List<ChatMessage>>>(
      aiChatProvider,
      (_, next) {
        final messages = next.value;
        if (messages == null || messages.isEmpty) {
          return;
        }
        final last = messages.last;
        if (last is AIChatMessage) {
          visibleAssistantUpdates.add(last.contentAsString);
        }
      },
    );
    addTearDown(subscription.close);

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this', false);
    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < 20; i++) {
      controller.add('rapid-$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final earlyVisible = _latestAssistantText(container);
    expect(earlyVisible, isNot('rapid-19'));
    expect(
      visibleAssistantUpdates.where((text) => text.startsWith('rapid-')).length,
      lessThan(20),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(_latestAssistantText(container), isNot('rapid-19'));

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(_latestAssistantText(container), 'rapid-19');
    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(aiChatStreamingProvider), isFalse);
  });

  test('startStreaming flushes pending assistant text when stream finishes',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-completion-flush-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this', false);
    await Future<void>.delayed(Duration.zero);

    controller.add('first');
    await Future<void>.delayed(Duration.zero);
    controller.add('final');
    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_latestAssistantText(container), 'final');
    expect(container.read(aiChatStreamingProvider), isFalse);
  });
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

void _configureAiProvider() {
  const providerId = 'openai';
  final provider = AiProviderMeta(
    id: providerId,
    name: 'OpenAI',
    type: AiProviderType.openaiCompatible,
    enabled: true,
    isBuiltIn: true,
    createdAt: 1,
    updatedAt: 1,
  );
  Prefs().selectedAiService = providerId;
  Prefs().aiProvidersV1 = [provider];
  Prefs().saveAiConfig(providerId, {
    'apiKey': 'test-key',
    'baseUrl': 'http://127.0.0.1.invalid/v1',
    'model': 'test-model',
  });
}

String _latestAssistantText(ProviderContainer container) {
  final messages = container.read(aiChatProvider).value;
  expect(messages, isNotNull);
  expect(messages, isNotEmpty);
  final last = messages!.last;
  expect(last, isA<AIChatMessage>());
  return last.contentAsString;
}
