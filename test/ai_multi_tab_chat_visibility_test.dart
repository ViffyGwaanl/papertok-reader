import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:papertok_reader/widgets/ai/ai_multi_tab_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugAiChatGenerateStreamOverride = null;
    _mockPathProvider(null);
  });

  testWidgets('AiMultiTabChat scopes UI visibility per tab', (tester) async {
    await _configureAiProvider();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: AiMultiTabChat(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AiChatStream), findsOneWidget);
    var firstContainer = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream).first),
    );
    expect(firstContainer.read(aiChatUiVisibleProvider), isTrue);

    final multiTabState =
        tester.state<AiMultiTabChatState>(find.byType(AiMultiTabChat));
    multiTabState.debugAddTab();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(multiTabState.debugTabCount, 2);
    final chatStreamFinder = find.byType(AiChatStream, skipOffstage: false);
    expect(chatStreamFinder, findsNWidgets(2));
    final chatElements = tester.elementList(chatStreamFinder).toList();
    firstContainer = ProviderScope.containerOf(chatElements[0]);
    final secondContainer = ProviderScope.containerOf(chatElements[1]);

    expect(firstContainer.read(aiChatUiVisibleProvider), isFalse);
    expect(secondContainer.read(aiChatUiVisibleProvider), isTrue);

    multiTabState.debugSwitchTab(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(firstContainer.read(aiChatUiVisibleProvider), isTrue);
    expect(secondContainer.read(aiChatUiVisibleProvider), isFalse);
  });

  testWidgets('external openSeminar shows inline runtime panel',
      (tester) async {
    await _configureAiProvider();
    final chatKey = GlobalKey<AiMultiTabChatState>();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: AiMultiTabChat(key: chatKey),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    chatKey.currentState!.openSeminar(
      question: 'Explain the source-grounded disagreement.',
      bookId: 9,
      sourceRef: SourceRef(
        bookId: 9,
        cfi: 'epubcfi(/6/10)',
        jumpLink: 'paperreader://reader/open?bookId=9&cfi=epubcfi(/6/10)',
        sourceTextSnippet: 'Grounded seminar seed.',
        sourceKind: SourceRefKind.reader,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
    expect(
      find.text('Explain the source-grounded disagreement.'),
      findsAtLeastNWidgets(1),
    );
    final panel = tester
        .widget<AiSeminarRuntimePanel>(find.byType(AiSeminarRuntimePanel));
    expect(panel.embedded, isTrue);
    expect(panel.initialSessionId, startsWith('seminar-chat-'));
  });

  testWidgets('closing a streaming tab cancels its generation subscription',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-tab-close-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      tempDir.deleteSync(recursive: true);
    });
    await _configureAiProvider();

    var canceled = false;
    final controller = StreamController<String>(
      onCancel: () {
        canceled = true;
      },
    );
    addTearDown(() async {
      if (!canceled && !controller.isClosed) {
        return;
      }
      if (!controller.isClosed) {
        await controller.close();
      }
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

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: AiMultiTabChat(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final multiTabState =
        tester.state<AiMultiTabChatState>(find.byType(AiMultiTabChat));
    final firstContainer = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream).first),
    );
    await firstContainer.read(aiChatProvider.future);

    firstContainer
        .read(aiChatProvider.notifier)
        .startStreaming('Keep explaining while tab closes', false);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(controller.hasListener, isTrue);

    multiTabState.debugAddTab();
    await tester.pump();
    multiTabState.debugCloseTab(0);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(canceled, isTrue);
  });
}

Future<void> _configureAiProvider() async {
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
    'aiConfig_$providerId': jsonEncode({
      'apiKey': 'test-key',
      'baseUrl': 'http://127.0.0.1.invalid/v1',
      'model': 'test-model',
    }),
  });
  await Prefs().initPrefs();
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
