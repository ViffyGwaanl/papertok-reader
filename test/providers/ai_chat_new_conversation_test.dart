import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
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
