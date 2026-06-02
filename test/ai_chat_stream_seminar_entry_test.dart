import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Add-to-Chat Seminar opens inline runtime without changing active style',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-entry-');
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
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
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
      await container.read(aiChatProvider.future);
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-entry',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('选择风格'), findsOneWidget);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      expect(find.byType(AiSeminarRuntimePage), findsNothing);
      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'Choose style Seminar row opens settings without selecting Seminar skill',
    (tester) async {
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
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(AiChatStream), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择风格'));
      await tester.pumpAndSettle();

      expect(find.text('研讨会设置'), findsOneWidget);

      await tester.tap(find.text('研讨会模式'));
      await tester.pumpAndSettle();

      expect(find.byType(AiSeminarConfigPage), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card reopens inline runtime',
    (tester) async {
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
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
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
      await container.read(aiChatProvider.future);
      final entry = _seminarCardHistoryEntry();
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('3 个角色'), findsOneWidget);
      expect(find.text('证据：当前书籍'), findsOneWidget);
      expect(find.text('写入需确认'), findsOneWidget);
      expect(find.byTooltip('研讨会设置'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      expect(find.widgetWithText(TextButton, '重新生成'), findsNothing);
      expect(find.widgetWithText(TextButton, '复制'), findsOneWidget);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
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

AiChatHistoryEntry _seminarCardHistoryEntry() {
  final human = ChatMessage.humanText('这个概念怎么理解？');
  final assistant = ChatMessage.ai('AI Seminar: 这个概念怎么理解？');
  const card = AiSeminarRunCardMeta(
    question: '这个概念怎么理解？',
    sessionId: 'seminar-chat-history',
    bookId: 7,
    status: 'ready',
    roleIds: ['critical', 'supportive', 'synthesizer'],
    evidenceScopeIds: ['current-book'],
    sourceRefCount: 0,
    allowWeb: false,
    writeRequiresApproval: true,
    maxRounds: 2,
    createdAt: 1234,
  );
  return AiChatHistoryEntry(
    id: 'seminar-card-history',
    serviceId: 'openai',
    model: 'gpt-test',
    createdAt: 1,
    updatedAt: 2,
    messages: [human, assistant],
    completed: true,
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
          'message': human.toMap(),
          'createdAt': 1,
          'updatedAt': 1,
        },
        'assistant-1': {
          'parentId': 'user-1',
          'children': <String>[],
          'activeChildId': null,
          'message': assistant.toMap(),
          'meta': const AiSegmentMeta(seminarRunCard: card).toJson(),
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}
