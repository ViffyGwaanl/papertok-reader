import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Seminar chat card hides role thinking while role partial is streaming',
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
      container
          .read(aiChatProvider.notifier)
          .loadHistoryEntry(_seminarStreamingHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('角色发言生成中'), findsOneWidget);
      expect(find.text('Streaming role partial from message part.'),
          findsOneWidget);
      expect(find.text('思考'), findsNothing);
      expect(find.text('Critical is preparing an evidence-grounded response.'),
          findsNothing);
    },
  );
}

AiChatHistoryEntry _seminarStreamingHistoryEntry() {
  final human = ChatMessage.humanText('这个概念怎么理解？');
  final assistant = ChatMessage.ai('AI Seminar: 这个概念怎么理解？');
  final card = AiSeminarRunCardMeta(
    question: '这个概念怎么理解？',
    sessionId: 'seminar-chat-history',
    bookId: 7,
    status: 'ready',
    roleIds: const ['critical', 'supportive', 'synthesizer'],
    evidenceScopeIds: const ['current-book'],
    sourceRefCount: 0,
    allowWeb: false,
    writeRequiresApproval: true,
    maxRounds: 2,
    createdAt: 1234,
    snapshot: const AiSeminarRunCardSnapshot(
      messageParts: [
        AiSeminarRunCardMessagePart(
          type: 'thinking',
          agentRunId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          roleId: 'critical',
          label: '批判者',
          text: 'Critical is preparing an evidence-grounded response.',
        ),
        AiSeminarRunCardMessagePart(
          type: 'role_partial',
          agentRunId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          roleId: 'critical',
          label: '批判者',
          text: 'Streaming role partial from message part.',
        ),
      ],
    ),
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
          'meta': {'seminarRunCard': card.toJson()},
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}
