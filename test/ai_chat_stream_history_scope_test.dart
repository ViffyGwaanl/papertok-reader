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
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('history drawer defaults to current book and can switch to all',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('ai-history-scope-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    const providerId = 'openai';
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
      'aiConfig_$providerId': jsonEncode({}),
    });

    await tester.runAsync(() async {
      await Prefs().initPrefs();
      await AiHistoryStore.upsertEntry(_entry(
        id: 'current',
        title: 'Current book conversation',
        bookId: 7,
        bookTitle: 'Scoped Book',
        updatedAt: 3,
      ));
      await AiHistoryStore.upsertEntry(_entry(
        id: 'other',
        title: 'Other book conversation',
        bookId: 8,
        bookTitle: 'Other Book',
        updatedAt: 2,
      ));
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const AiChatStream(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream)),
    );
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: Book.mock().copyWith(id: 7, title: 'Scoped Book'),
          ),
        );
    await tester.runAsync(() async {
      await container.read(aiHistoryProvider.notifier).refresh();
    });
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('History'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Current book'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Current book conversation'), findsOneWidget);
    expect(find.text('Other book conversation'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Current book conversation'), findsOneWidget);
    expect(find.text('Other book conversation'), findsOneWidget);

    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: Book.mock().copyWith(id: 8, title: 'Other Book'),
          ),
        );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Current book conversation'), findsNothing);
    expect(find.text('Other book conversation'), findsOneWidget);
  });
}

AiChatHistoryEntry _entry({
  required String id,
  required String title,
  required int bookId,
  required String bookTitle,
  required int updatedAt,
}) {
  return AiChatHistoryEntry(
    id: id,
    serviceId: 'openai',
    model: 'gpt-test',
    createdAt: 1,
    updatedAt: updatedAt,
    title: title,
    titleSource: 'manual',
    messages: [ChatMessage.humanText(title)],
    completed: true,
    bookId: bookId,
    bookTitle: bookTitle,
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
