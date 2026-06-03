import 'dart:async';
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
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
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
    'AI Chat Seminar run setup persists single-run role prompt and rounds',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-run-setup-');
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
      Prefs().aiSeminarRoleProfiles = [
        AiSeminarRoleProfile(
          role: AiSeminarRole.critical,
          evidenceScopes: const [AiSeminarEvidenceScope.library],
          allowedToolIds: const ['semantic_search_current_book'],
        ),
      ];
      expect(
        Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.evidenceScopes,
        const [AiSeminarEvidenceScope.library],
      );

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

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-chat-seminar-run-setup')));
      await tester.pumpAndSettle();

      expect(find.text('本次研讨设置'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('seminar-run-max-rounds')),
        '4',
      );
      await tester.enterText(
        find.byKey(const ValueKey('seminar-run-role-critical-prompt')),
        '请先指出反方证据缺口，再决定是否需要刷新证据。',
      );
      await tester
          .ensureVisible(find.byKey(const ValueKey('seminar-run-start')));
      await tester.tap(find.byKey(const ValueKey('seminar-run-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final criticalProfile = card?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.critical,
      );
      expect(card?.maxRounds, 4);
      expect(criticalProfile?.customPrompt, '请先指出反方证据缺口，再决定是否需要刷新证据。');
      expect(criticalProfile?.evidenceScopes,
          const [AiSeminarEvidenceScope.library]);
      expect(
        criticalProfile?.allowedToolIds,
        const ['semantic_search_current_book'],
      );
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
      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('角色观点'), findsNothing);
      expect(find.text('1 · 批判者'), findsOneWidget);
      expect(
          find.text('This claim needs a boundary condition.'), findsOneWidget);
      expect(find.text('2 · 支持者'), findsOneWidget);
      expect(
          find.text('The surrounding paragraph supports it.'), findsOneWidget);
      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('The group agrees on the mechanism but not the scope.'),
          findsOneWidget);
      expect(find.text('1 个分歧'), findsOneWidget);
      expect(find.byTooltip('研讨会设置'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      expect(find.widgetWithText(TextButton, '重新生成'), findsNothing);
      expect(find.widgetWithText(TextButton, '复制'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '角色'));
      await tester.pumpAndSettle();

      expect(find.text('角色观点'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(
          find.text('This claim needs a boundary condition.'), findsOneWidget);
      expect(find.text('支持者'), findsOneWidget);
      expect(
          find.text('The surrounding paragraph supports it.'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-question-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card surfaces a resumable checkpoint',
    (tester) async {
      const providerId = 'openai';
      const sessionId = 'seminar-chat-history';
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
      final runningState = _resumableSeminarRuntimeState(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(runningState.toJson()),
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              AiSeminarRuntimeService(
                fetchEvidence: (_) async {
                  fail('opening the resume card should not refetch evidence');
                },
                streamRole: (_, __) async* {
                  fail('opening the resume card should not call a role model');
                },
              ),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('可从中断处继续'), findsOneWidget);
      expect(find.textContaining('已完成 1 个角色'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '打开恢复'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey('seminar-chat-card-resume-$sessionId'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-resume-$sessionId'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card continues checkpoint directly',
    (tester) async {
      const providerId = 'openai';
      const sessionId = 'seminar-chat-history';
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
      final invokedRoles = <AiSeminarRole>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(_resumableSeminarRuntimeState(sessionId).toJson()),
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              AiSeminarRuntimeService(
                fetchEvidence: (_) async {
                  fail('direct resume should reuse persisted evidence');
                },
                streamRole: (invocation, _) async* {
                  invokedRoles.add(invocation.role);
                  yield AiSeminarRoleStreamChunk(
                    completedTurn: AiSeminarRoleTurn(
                      id: 'turn-${invocation.role.asString}',
                      role: invocation.role,
                      prompt: invocation.prompt,
                      responseText: '${invocation.role.asString} response',
                      evidenceRefIds: const ['e1'],
                    ),
                  );
                },
                now: () => 1000,
              ),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(invokedRoles, isEmpty);
      expect(
        find.byKey(
          const ValueKey('seminar-chat-card-continue-$sessionId'),
        ),
        findsOneWidget,
      );
      expect(find.text('继续研讨'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey('seminar-chat-card-continue-$sessionId'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-continue-$sessionId'),
        ),
      );
      for (var i = 0; i < 20 && invokedRoles.length < 2; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(invokedRoles, [
        AiSeminarRole.supportive,
        AiSeminarRole.synthesizer,
      ]);
      final state = container.read(
        aiSeminarRuntimeScopedProvider(sessionId),
      );
      expect(state.status, AiSeminarRunStatus.completed);
      expect(state.turns.map((turn) => turn.role), [
        AiSeminarRole.critical,
        AiSeminarRole.supportive,
        AiSeminarRole.synthesizer,
      ]);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card ignores duplicate continue taps while running',
    (tester) async {
      const providerId = 'openai';
      const sessionId = 'seminar-chat-history';
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
      final releaseFirstRole = Completer<void>();
      final invokedRoles = <AiSeminarRole>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(_resumableSeminarRuntimeState(sessionId).toJson()),
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              AiSeminarRuntimeService(
                fetchEvidence: (_) async {
                  fail('direct resume should reuse persisted evidence');
                },
                streamRole: (invocation, _) async* {
                  invokedRoles.add(invocation.role);
                  if (invocation.role == AiSeminarRole.supportive) {
                    await releaseFirstRole.future;
                  }
                  yield AiSeminarRoleStreamChunk(
                    completedTurn: AiSeminarRoleTurn(
                      id: 'turn-${invocation.role.asString}',
                      role: invocation.role,
                      prompt: invocation.prompt,
                      responseText: '${invocation.role.asString} response',
                      evidenceRefIds: const ['e1'],
                    ),
                  );
                },
                now: () => 1000,
              ),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final continueButton = find.byKey(
        const ValueKey('seminar-chat-card-continue-$sessionId'),
      );
      final openButton = find.byKey(
        const ValueKey('seminar-chat-card-resume-$sessionId'),
      );
      await tester.ensureVisible(continueButton);
      await tester.pumpAndSettle();

      await tester.tap(continueButton);
      for (var i = 0; i < 20 && invokedRoles.isEmpty; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(invokedRoles, [AiSeminarRole.supportive]);
      await tester.pump();

      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(openButton).onPressed, isNull);

      await tester.tap(continueButton, warnIfMissed: false);
      await tester.tap(openButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(invokedRoles, [AiSeminarRole.supportive]);

      releaseFirstRole.complete();
      for (var i = 0; i < 20 && invokedRoles.length < 2; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(invokedRoles, [
        AiSeminarRole.supportive,
        AiSeminarRole.synthesizer,
      ]);
      final state = container.read(
        aiSeminarRuntimeScopedProvider(sessionId),
      );
      expect(state.status, AiSeminarRunStatus.completed);
    },
  );

  testWidgets(
    'persisted Seminar chat card hides resume banner for another checkpoint',
    (tester) async {
      const providerId = 'openai';
      const otherSessionId = 'other-seminar-session';
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
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(otherSessionId)}':
            jsonEncode(_resumableSeminarRuntimeState(otherSessionId).toJson()),
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('可从中断处继续'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '打开恢复'), findsNothing);
    },
  );

  testWidgets(
    'inline Seminar completion updates persisted chat card snapshot',
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
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
          ],
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
      final entry = _seminarCardHistoryEntry(includeSnapshot: false);
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('证据快照'), findsNothing);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'completed');
      expect(card?.sourceRefCount, 4);
      expect(card?.snapshot?.evidence, hasLength(3));
      expect(card?.snapshot?.evidence.first.snippet, 'The source passage.');
      expect(
        card?.snapshot?.evidence.map((item) => item.snippet),
        isNot(contains('Unused source passage 5.')),
      );
      expect(card?.snapshot?.roleSummaries.first.summary, 'critical response');
      expect(card?.snapshot?.synthesisSummary, 'synthesizer response');
      expect(card?.snapshot?.disagreements, ['Scope remains disputed.']);
      final disagreement = card?.snapshot?.disagreementDetails.single;
      expect(disagreement?.text, 'Scope remains disputed.');
      expect(disagreement?.roleIds, ['critical']);
      expect(disagreement?.evidenceRefs.single.id, 'e1');
      expect(disagreement?.evidenceRefs.single.snippet, 'The source passage.');
    },
  );

  testWidgets(
    'persisted Seminar chat card shows whiteboard items from snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('研讨白板'), findsOneWidget);
      expect(find.text('分歧'), findsAtLeastNWidgets(1));
      expect(find.text('Scope remains disputed.'), findsOneWidget);
      expect(find.text('开放问题'), findsOneWidget);
      expect(find.text('What evidence would resolve scope?'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card shows a discussion timeline with role evidence',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeRoleEvidenceRefs: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('1 · 批判者'), findsOneWidget);
      expect(find.text('2 · 支持者'), findsOneWidget);
      expect(find.text('本轮证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsWidgets);
    },
  );

  testWidgets(
    'persisted Seminar chat card exposes source action for evidence',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshotSourceRef: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('打开来源'), findsWidgets);
    },
  );

  testWidgets(
    'persisted Seminar evidence source action emits reader URI',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final opened = <Uri>[];

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
            home: AiChatStream(
              sourceOpener: (_, uri) async => opened.add(uri),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshotSourceRef: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('打开来源').first);
      await tester.pump();

      expect(opened, hasLength(1));
      expect(opened.single.scheme, 'paperreader');
      expect(opened.single.host, 'reader');
      expect(opened.single.path, '/open');
      expect(opened.single.queryParameters['bookId'], '7');
      expect(opened.single.queryParameters['cfi'], 'epubcfi(/6/8)');
    },
  );

  testWidgets(
    'persisted Seminar unavailable evidence source explains reason',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final opened = <Uri>[];

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
            home: AiChatStream(
              sourceOpener: (_, uri) async => opened.add(uri),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeUnavailableSnapshotSourceRef: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('来源不可用'), findsWidgets);
      await tester.tap(find.text('来源不可用').first);
      await tester.pump();

      expect(opened, isEmpty);
      expect(find.text('source book was removed'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card switches snapshot subviews to disagreements',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              extraLegacyDisagreement: 'Method remains unclear.',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('2 个分歧'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('分歧视图'), findsOneWidget);
      expect(find.text('Scope remains disputed.'), findsAtLeastNWidgets(1));
      expect(find.text('Method remains unclear.'), findsOneWidget);
      expect(find.text('关联角色'), findsOneWidget);
      expect(find.text('批判者、支持者'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('证据快照'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-evidence-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('分歧视图'), findsNothing);
    },
  );

  testWidgets(
    'Seminar chat card hides Review handoff for a different active run',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-hide-');
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
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(
              aiSeminarRuntimeScopedProvider('other-seminar-session').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'other-seminar-session',
              question: '另一个研讨',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('发送到待审'), findsNothing);
    },
  );

  testWidgets(
    'Seminar chat card sends active completed run to exception Review',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(includeReviewCandidates: true),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
          ],
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

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('异常送审'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-review-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('异常处理预览'), findsOneWidget);
      expect(find.text('只在低置信、冲突或来源异常时发送到 Review Inbox'), findsOneWidget);
      expect(find.text('异常原因'), findsOneWidget);
      expect(find.text('存在未解决分歧：1 项'), findsOneWidget);
      expect(find.text('包含知识卡候选：1 项'), findsOneWidget);
      expect(find.text('包含复习候选：1 项'), findsOneWidget);
      expect(find.text('综合总结'), findsOneWidget);
      expect(find.text('synthesizer response'), findsOneWidget);
      expect(find.text('可追踪证据：3 条'), findsOneWidget);
      expect(find.text('异常送审内容'), findsOneWidget);
      expect(find.text('综合总结：1 项'), findsOneWidget);
      expect(find.text('知识卡候选：1 项'), findsOneWidget);
      expect(find.text('Exception card candidate'), findsOneWidget);
      expect(find.text('候选证据'), findsWidgets);
      expect(find.text('Additional source passage 4.'), findsOneWidget);
      expect(find.text('复习候选：1 项'), findsOneWidget);
      expect(find.text('What boundary should be reviewed?'), findsOneWidget);
      expect(find.text('综合证据'), findsOneWidget);
      expect(find.text('The source passage.'), findsOneWidget);
      expect(find.text('普通学习保存请优先使用知识卡、复习或我的图谱。'), findsOneWidget);

      await tester.tap(find.text('异常送审'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(AiSeminarRuntimePanel), findsNothing);

      final pendingItems =
          await reviewStore.list(status: ReviewItemStatus.pending);
      final appliedItems =
          await reviewStore.list(status: ReviewItemStatus.applied);
      final seminarCards =
          await cardStore.list(origin: KnowledgeCardOrigin.seminar);
      final synthesis = pendingItems.singleWhere(
        (item) => item.sourceType == ReviewItemSourceType.seminarSynthesis,
      );

      expect(synthesis.payload['summary'], 'synthesizer response');
      expect(synthesis.sourceRefs, isNotEmpty);
      expect(synthesis.sourceRefs.every((ref) => ref.hasEvidence), true);
      expect(
        pendingItems.map((item) => item.sourceType).toSet(),
        containsAll({
          ReviewItemSourceType.seminarSynthesis,
          ReviewItemSourceType.knowledgeCard,
          ReviewItemSourceType.flashcardCandidate,
        }),
      );
      expect(seminarCards.single.title, 'Exception card candidate');
      expect(appliedItems, isEmpty);
      expect(find.textContaining('已将综合总结和 1 张卡片送入异常待审。'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card saves synthesis as a draft KnowledgeCard inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('保存知识卡'), findsOneWidget);

      await tester.tap(find.text('保存知识卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final seminarCards =
          await cardStore.list(origin: KnowledgeCardOrigin.seminar);
      final reviewItems = await reviewStore.list();

      expect(seminarCards, hasLength(1));
      expect(seminarCards.single.reviewState, KnowledgeCardReviewState.draft);
      expect(seminarCards.single.title, 'AI Seminar synthesis');
      expect(seminarCards.single.explanation, 'synthesizer response');
      expect(seminarCards.single.sourceRefs, isNotEmpty);
      expect(
        seminarCards.single.sourceRefs.every((ref) => ref.hasEvidence),
        true,
      );
      expect(reviewItems, isEmpty);
      expect(find.textContaining('已保存为知识卡'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card edits synthesis before saving a KnowledgeCard inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('编辑后保存'), findsOneWidget);

      await tester.tap(find.text('编辑后保存'));
      await tester.pumpAndSettle();

      expect(find.text('编辑知识卡'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('seminar-card-edit-title')),
        '读者改过的标题',
      );
      await tester.enterText(
        find.byKey(const ValueKey('seminar-card-edit-explanation')),
        '读者改过的解释',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final seminarCards =
          await cardStore.list(origin: KnowledgeCardOrigin.seminar);

      expect(seminarCards, hasLength(1));
      expect(seminarCards.single.reviewState, KnowledgeCardReviewState.draft);
      expect(seminarCards.single.title, '读者改过的标题');
      expect(seminarCards.single.explanation, '读者改过的解释');
      expect(seminarCards.single.sourceRefs, isNotEmpty);
      expect(await reviewStore.list(), isEmpty);
      expect(find.text('撤销保存'), findsOneWidget);
      expect(find.textContaining('已保存为知识卡'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card can undo an inline draft KnowledgeCard save',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('保存知识卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        hasLength(1),
      );
      expect(find.text('撤销保存'), findsOneWidget);

      await tester.tap(find.text('撤销保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        isEmpty,
      );
      expect(await reviewStore.list(), isEmpty);
      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.textContaining('已撤销知识卡保存'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card ignores low-burden asset actions inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();
      final spacedReviewStore = _MemorySpacedReviewStore();
      final graphStore = _MemoryConceptGraphStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
            spacedReviewStoreProvider.overrideWithValue(spacedReviewStore),
            conceptGraphStoreProvider.overrideWithValue(graphStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('编辑后保存'), findsOneWidget);
      expect(find.text('加入复习'), findsOneWidget);
      expect(find.text('加入我的图谱'), findsOneWidget);
      expect(find.text('忽略'), findsOneWidget);

      await tester.tap(find.text('忽略'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(await reviewStore.list(), isEmpty);
      expect(
          await cardStore.list(origin: KnowledgeCardOrigin.seminar), isEmpty);
      expect(await spacedReviewStore.list(dueOnly: false), isEmpty);
      expect(await graphStore.listNodes(), isEmpty);
      expect(find.text('保存知识卡'), findsNothing);
      expect(find.text('编辑后保存'), findsNothing);
      expect(find.text('加入复习'), findsNothing);
      expect(find.text('加入我的图谱'), findsNothing);
      expect(find.text('已忽略本次沉淀建议'), findsOneWidget);
      expect(find.text('恢复操作'), findsOneWidget);

      await tester.tap(find.text('恢复操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('编辑后保存'), findsOneWidget);
      expect(find.text('加入复习'), findsOneWidget);
      expect(find.text('加入我的图谱'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card adds synthesis to spaced review inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();
      final spacedReviewStore = _MemorySpacedReviewStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
            spacedReviewStoreProvider.overrideWithValue(spacedReviewStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('加入复习'), findsOneWidget);

      await tester.tap(find.text('加入复习'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final reviewItems = await reviewStore.list();
      final spacedItems = await spacedReviewStore.list(dueOnly: false);

      expect(reviewItems, isEmpty);
      expect(spacedItems, hasLength(1));
      expect(
        spacedItems.single.id,
        SpacedReviewStore.reviewIdForFlashcard(
          'seminar:seminar-chat-history:synthesis-review',
        ),
      );
      expect(spacedItems.single.prompt, '复习这场 AI Seminar 的结论');
      expect(spacedItems.single.answer, 'synthesizer response');
      expect(spacedItems.single.sourceRefs, isNotEmpty);
      expect(
          spacedItems.single.sourceRefs.every((ref) => ref.hasEvidence), true);
      expect(find.text('撤销复习'), findsOneWidget);
      expect(find.textContaining('已加入复习'), findsOneWidget);

      await tester.tap(find.text('撤销复习'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(await spacedReviewStore.list(dueOnly: false), isEmpty);
      expect(await reviewStore.list(), isEmpty);
      expect(find.text('加入复习'), findsOneWidget);
      expect(find.textContaining('已撤销复习'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card adds synthesis to my graph inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
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
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();
      final graphStore = _MemoryConceptGraphStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
            conceptGraphStoreProvider.overrideWithValue(graphStore),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('加入我的图谱'), findsOneWidget);

      await tester.tap(find.text('加入我的图谱'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final graphNodes = await graphStore.listNodes();
      final reviewItems = await reviewStore.list();

      expect(reviewItems, isEmpty);
      expect(graphNodes, hasLength(1));
      expect(
          graphNodes.single.id, 'seminar:seminar-chat-history:synthesis-node');
      expect(graphNodes.single.type, ConceptNodeType.claim);
      expect(graphNodes.single.label, 'synthesizer response');
      expect(graphNodes.single.summary, 'synthesizer response');
      expect(graphNodes.single.sourceRefs, isNotEmpty);
      expect(
          graphNodes.single.sourceRefs.every((ref) => ref.hasEvidence), true);
      expect(graphNodes.single.ownership, AiOutputOwnership.aiGeneratedDraft);
      expect(find.text('撤销图谱'), findsOneWidget);
      expect(find.textContaining('已加入我的图谱'), findsOneWidget);

      await tester.tap(find.text('撤销图谱'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(await graphStore.listNodes(), isEmpty);
      expect(await reviewStore.list(), isEmpty);
      expect(find.text('加入我的图谱'), findsOneWidget);
      expect(find.textContaining('已撤销图谱保存'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card accepts a run-scoped reader turn',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final prompts = <String>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarCardComposerService(prompts),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('读者参与'), findsOneWidget);
      await tester.enterText(
        find.byKey(
          const ValueKey('seminar-chat-card-reply-seminar-chat-history'),
        ),
        '请批判者针对此处范围争议继续反驳。',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-ask-role-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(state.turns.last.id, 'turn-critical-follow-up');
      expect(state.turns.last.responseText, 'critical follow-up response');
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.askRole,
      );
      expect(
        state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.critical,
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
      expect(
        prompts.last,
        contains('Reader intervention: 请批判者针对此处范围争议继续反驳。'),
      );
      expect(find.text('critical follow-up response'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card surfaces a Director askUser reader turn',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final prompts = <String>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarCardAskUserService(prompts),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final askUserState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(askUserState.status, AiSeminarRunStatus.completed);
      expect(
        askUserState.directorState!.nextIntent,
        AiSeminarDirectorNextIntent.askUser,
      );
      expect(askUserState.directorState!.needsUserInput, true);
      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('读者参与'), findsOneWidget);
      expect(find.text('主持人正在等待你的回应'), findsOneWidget);
      expect(
        find.text('Which interpretation should the reader test next?'),
        findsAtLeastNWidgets(1),
      );

      await tester.enterText(
        find.byKey(
          const ValueKey('seminar-chat-card-reply-seminar-chat-history'),
        ),
        '我想先让批判者回应这个开放问题。',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-ask-role-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(state.turns.last.id, 'turn-critical-follow-up');
      expect(state.turns.last.responseText, 'critical follow-up response');
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.askRole,
      );
      expect(
        state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.critical,
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
      expect(
        prompts.last,
        contains('Reader intervention: 我想先让批判者回应这个开放问题。'),
      );
      expect(find.text('critical follow-up response'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card continues directly from a disagreement',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final prompts = <String>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarCardDisagreementService(prompts),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('分歧继续讨论'), findsOneWidget);
      expect(find.text('Scope remains disputed.'), findsAtLeastNWidgets(1));
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-ask-critical-disagreement-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(state.turns.last.id, 'turn-critical-follow-up');
      expect(state.turns.last.responseText, 'critical follow-up response');
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.askRole,
      );
      expect(
        state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.critical,
      );
      expect(
        state.directorState!.lastUserIntervention!.text,
        '围绕分歧继续反驳：Scope remains disputed.',
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
      expect(
        prompts.last,
        contains('Reader intervention: 围绕分歧继续反驳：Scope remains disputed.'),
      );
    },
  );

  testWidgets(
    'Seminar chat card refreshes evidence directly from a disagreement',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final prompts = <String>[];
      final evidenceFetches = <String>[];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarCardDisagreementRefreshService(
                prompts,
                evidenceFetches,
              ),
            ),
          ],
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(evidenceFetches, ['e1']);
      expect(find.text('分歧继续讨论'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-refresh-disagreement-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(evidenceFetches, ['e1', 'e2']);
      expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e2']);
      expect(state.turns.map((turn) => turn.id), [
        'turn-critical-e2',
        'turn-supportive-e2',
        'turn-synthesizer-e2',
      ]);
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.refreshEvidence,
      );
      expect(
        state.directorState!.lastUserIntervention!.text,
        '围绕分歧重新找证据：Scope remains disputed.',
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
      expect(state.synthesis!.summary, 'synthesizer response using e2');
      expect(
        prompts.last,
        contains('Evidence ids: e2'),
      );
    },
  );
}

class _MemoryReviewItemStore extends ReviewItemStore {
  final _items = <String, ReviewItem>{};

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return _items.values.where((item) {
      if (status != null && item.status != status) return false;
      if (sourceType != null && item.sourceType != sourceType) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<ReviewItem?> getById(String id) async => _items[id];

  @override
  Future<ReviewItem> upsert(ReviewItem item) async {
    if (item.status != ReviewItemStatus.draft &&
        item.status != ReviewItemStatus.pending) {
      throw ArgumentError(
        'Only draft/pending review items can be staged.',
      );
    }
    _items[item.id] = item;
    return item;
  }
}

class _MemoryKnowledgeCardStore extends KnowledgeCardStore {
  final _cards = <KnowledgeCard>[];

  @override
  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) async {
    return _cards.where((card) {
      if (reviewState != null && card.reviewState != reviewState) {
        return false;
      }
      if (origin != null && card.origin != origin) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<KnowledgeCard?> getById(String id) async {
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  @override
  Future<bool> removeDraftCandidate(String id) async {
    final index = _cards.indexWhere((card) => card.id == id);
    if (index < 0) return false;
    final card = _cards[index];
    final isStaged = card.reviewState == KnowledgeCardReviewState.draft ||
        card.reviewState == KnowledgeCardReviewState.pending;
    if (!isStaged ||
        card.ownership != AiOutputOwnership.aiGeneratedDraft ||
        card.isUserAsset) {
      return false;
    }
    _cards.removeAt(index);
    return true;
  }

  @override
  Future<KnowledgeCardStoreUpsertResult> upsertCandidate(
    KnowledgeCard candidate,
  ) async {
    for (final card in _cards) {
      if (card.id == candidate.id ||
          KnowledgeCardDedupe.isLikelyDuplicate(card, candidate)) {
        return KnowledgeCardStoreUpsertResult(
          card: card,
          inserted: false,
          duplicateOfId: card.id,
        );
      }
    }
    final staged = candidate.copyWith(
      reviewState: candidate.reviewState == KnowledgeCardReviewState.draft
          ? KnowledgeCardReviewState.draft
          : KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
    _cards.add(staged);
    return KnowledgeCardStoreUpsertResult(card: staged, inserted: true);
  }
}

class _MemorySpacedReviewStore extends SpacedReviewStore {
  _MemorySpacedReviewStore() : super(rootDir: Directory.systemTemp);

  final _items = <SpacedReviewItem>[];

  @override
  Future<List<SpacedReviewItem>> list({
    bool dueOnly = false,
    int? now,
  }) async {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final filtered = dueOnly
        ? _items.where((item) => item.isDue(timestamp)).toList()
        : _items.toList();
    filtered.sort((a, b) => (a.dueAt ?? 0).compareTo(b.dueAt ?? 0));
    return filtered;
  }

  @override
  Future<SpacedReviewItem?> getById(String id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<SpacedReviewItem> upsertInlineFlashcard({
    required String flashcardId,
    required String prompt,
    required String answer,
    List<SourceRef> sourceRefs = const <SourceRef>[],
    int? now,
  }) async {
    if (!sourceRefs.any((ref) => ref.hasEvidence)) {
      throw StateError(
        'Inline flashcard cannot enter spaced review without SourceRef.',
      );
    }
    final id = SpacedReviewStore.reviewIdForFlashcard(flashcardId.trim());
    final candidate = SpacedReviewItem(
      id: id,
      cardId: flashcardId.trim(),
      prompt: prompt.trim(),
      answer: answer.trim(),
      sourceRefs: sourceRefs,
      dueAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _items[index] = candidate;
    } else {
      _items.add(candidate);
    }
    return candidate;
  }

  @override
  Future<bool> removeInlineFlashcard(String flashcardId) async {
    final id = SpacedReviewStore.reviewIdForFlashcard(flashcardId.trim());
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final item = _items[index];
    if (item.lastReviewedAt != null || item.reviewHistory.isNotEmpty) {
      return false;
    }
    _items.removeAt(index);
    return true;
  }
}

class _MemoryConceptGraphStore extends ConceptGraphStore {
  _MemoryConceptGraphStore() : super(rootDir: Directory.systemTemp);

  final _nodes = <ConceptNode>[];
  final _edges = <ConceptEdge>[];

  @override
  Future<List<ConceptNode>> listNodes() async => List<ConceptNode>.from(_nodes);

  @override
  Future<List<ConceptEdge>> listEdges() async => List<ConceptEdge>.from(_edges);

  @override
  Future<ConceptNode> upsertNode(ConceptNode node) async {
    final draft = ConceptNode(
      id: node.id,
      type: node.type,
      label: node.label,
      summary: node.summary,
      sourceRefs: node.sourceRefs,
      cardIds: node.cardIds,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: node.createdAt,
      updatedAt: node.updatedAt,
    );
    final index = _nodes.indexWhere((entry) => entry.id == draft.id);
    if (index >= 0) {
      _nodes[index] = draft;
    } else {
      _nodes.add(draft);
    }
    return draft;
  }

  @override
  Future<bool> removeDraftNode(String nodeId) async {
    final index = _nodes.indexWhere((entry) => entry.id == nodeId.trim());
    if (index < 0) return false;
    if (_nodes[index].ownership != AiOutputOwnership.aiGeneratedDraft) {
      return false;
    }
    _nodes.removeAt(index);
    _edges.removeWhere(
      (edge) => edge.sourceNodeId == nodeId || edge.targetNodeId == nodeId,
    );
    return true;
  }
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

AiSeminarRuntimeState _resumableSeminarRuntimeState(String sessionId) {
  final evidenceBundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e1',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'The source passage.',
        sourceRef: SourceRef(
          bookId: 7,
          href: 'Text/ch1.xhtml',
          cfi: 'epubcfi(/6/8)',
          jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
          sourceTextSnippet: 'The source passage.',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ),
    ],
  );
  final backgroundJob = AiSeminarBackgroundJobSnapshot(
    id: 'job-$sessionId',
    sessionId: sessionId,
    status: AiSeminarBackgroundJobStatus.running,
    startedAt: 1000,
    updatedAt: 1001,
  );
  return AiSeminarRuntimeState.initial().copyWith(
    session: AiSeminarSessionContract(
      id: sessionId,
      question: '这个概念怎么理解？',
      bookId: 7,
      billingContext: const AiSeminarBillingContext(
        providerId: 'openai',
        providerName: 'OpenAI',
        providerType: 'openai',
        modelId: 'gpt-test',
      ),
    ),
    status: AiSeminarRunStatus.running,
    evidenceBundle: evidenceBundle,
    turns: const [
      AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'critical prompt',
        responseText: 'critical response',
        evidenceRefIds: ['e1'],
      ),
    ],
    backgroundJob: backgroundJob,
    backgroundJobs: [backgroundJob],
  );
}

AiChatHistoryEntry _seminarCardHistoryEntry({
  bool includeSnapshot = true,
  String? extraLegacyDisagreement,
  bool includeRoleEvidenceRefs = false,
  bool includeSnapshotSourceRef = false,
  bool includeUnavailableSnapshotSourceRef = false,
}) {
  final human = ChatMessage.humanText('这个概念怎么理解？');
  final assistant = ChatMessage.ai('AI Seminar: 这个概念怎么理解？');
  final snapshot = includeSnapshot
      ? AiSeminarRunCardSnapshot(
          evidence: const [
            AiSeminarRunCardEvidenceSnapshot(
              title: 'Working memory',
              snippet: 'Working memory evidence.',
            ),
          ],
          roleSummaries: const [
            AiSeminarRunCardRoleSummary(
              roleId: 'critical',
              label: '批判者',
              summary: 'This claim needs a boundary condition.',
            ),
            AiSeminarRunCardRoleSummary(
              roleId: 'supportive',
              label: '支持者',
              summary: 'The surrounding paragraph supports it.',
            ),
          ],
          synthesisSummary:
              'The group agrees on the mechanism but not the scope.',
          disagreements: [
            'Scope remains disputed.',
            if (extraLegacyDisagreement != null) extraLegacyDisagreement,
          ],
          disagreementDetails: const [
            AiSeminarRunCardDisagreementDetail(
              text: 'Scope remains disputed.',
              roleIds: ['critical', 'supportive'],
              evidenceRefs: [
                AiSeminarRunCardEvidenceSnapshot(
                  id: 'e1',
                  title: 'Working memory',
                  snippet: 'Working memory evidence.',
                ),
              ],
            ),
          ],
          openQuestions: const ['What evidence would resolve scope?'],
        )
      : null;
  final card = AiSeminarRunCardMeta(
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
    snapshot: snapshot,
  );
  final cardJson = card.toJson();
  if (includeSnapshotSourceRef || includeUnavailableSnapshotSourceRef) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      final sourceRefJson = includeUnavailableSnapshotSourceRef
          ? {
              'sourceTitle': 'Chapter 2',
              'locationLabel': 'Section 2.1',
              'sourceTextSnippet': 'Working memory evidence.',
              'sourceKind': 'current-book-rag',
              'unavailableReason': 'source book was removed',
            }
          : {
              'bookId': 7,
              'href': 'Text/ch2.xhtml',
              'cfi': 'epubcfi(/6/8)',
              'jumpLink':
                  'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
              'sourceTitle': 'Chapter 2',
              'locationLabel': 'Section 2.1',
              'sourceTextSnippet': 'Working memory evidence.',
              'sourceKind': 'current-book-rag',
            };
      void attachSourceRef(Object? rawEvidence) {
        if (rawEvidence is Map) {
          rawEvidence['sourceRef'] = Map<String, Object>.from(sourceRefJson);
        }
      }

      final evidence = snapshotJson['evidence'];
      if (evidence is List) {
        for (final item in evidence) {
          attachSourceRef(item);
        }
      }
      final roleSummaries = snapshotJson['roleSummaries'];
      if (roleSummaries is List) {
        for (final role in roleSummaries) {
          if (role is! Map) continue;
          final evidenceRefs = role['evidenceRefs'];
          if (evidenceRefs is List) {
            for (final item in evidenceRefs) {
              attachSourceRef(item);
            }
          }
        }
      }
      final disagreementDetails = snapshotJson['disagreementDetails'];
      if (disagreementDetails is List) {
        for (final detail in disagreementDetails) {
          if (detail is! Map) continue;
          final evidenceRefs = detail['evidenceRefs'];
          if (evidenceRefs is List) {
            for (final item in evidenceRefs) {
              attachSourceRef(item);
            }
          }
        }
      }
    }
  }
  if (includeRoleEvidenceRefs) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      final roleSummaries = snapshotJson['roleSummaries'];
      if (roleSummaries is List && roleSummaries.isNotEmpty) {
        final firstRole = roleSummaries.first;
        if (firstRole is Map) {
          firstRole['evidenceRefs'] = [
            {
              'id': 'e1',
              'title': 'Working memory',
              'snippet': 'Working memory evidence.',
            },
          ];
        }
      }
    }
  }
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
          'meta': {'seminarRunCard': cardJson},
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}

AiSeminarRuntimeService _seminarSnapshotService({
  bool includeReviewCandidates = false,
}) {
  final sourceRefs = List<SourceRef>.generate(
    5,
    (index) => SourceRef(
      bookId: 7,
      href: 'Text/ch${index + 1}.xhtml',
      cfi: 'epubcfi(/6/${8 + index})',
      jumpLink:
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/${8 + index}%29',
      sourceTextSnippet: index == 0
          ? 'The source passage.'
          : index == 4
              ? 'Unused source passage 5.'
              : 'Additional source passage ${index + 1}.',
      sourceKind: SourceRefKind.currentBookRag,
    ),
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      for (var i = 0; i < sourceRefs.length; i++)
        AiSeminarEvidence(
          id: 'e${i + 1}',
          scope: AiSeminarEvidenceScope.currentBook,
          text: i == 0
              ? 'The source passage.'
              : i == 4
                  ? 'Unused source passage 5.'
                  : 'Additional source passage ${i + 1}.',
          sourceRef: sourceRefs[i],
        ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: switch (invocation.role) {
            AiSeminarRole.critical => const ['e1', 'e2'],
            AiSeminarRole.supportive => const ['e3'],
            _ => const ['e4'],
          },
          whiteboardEntries: [
            if (invocation.role == AiSeminarRole.critical)
              const AiSeminarWhiteboardEntry(
                id: 'disagreement-1',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Scope remains disputed.',
                role: AiSeminarRole.critical,
                evidenceRefIds: ['e1'],
              ),
            if (includeReviewCandidates &&
                invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'candidate-card-1',
                kind: AiSeminarWhiteboardKind.candidateCard,
                text: 'Exception card candidate',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e4'],
                conceptRefs: ['Exception concept'],
              ),
            if (includeReviewCandidates &&
                invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'review-question-1',
                kind: AiSeminarWhiteboardKind.reviewSuggestion,
                text: 'What boundary should be reviewed?',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e4'],
              ),
          ],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarCardAskUserService(List<String> prompts) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e1',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'The source passage.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      prompts.add(invocation.prompt);
      final isFollowUp = invocation.prompt.contains('Reader intervention:');
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: isFollowUp
              ? 'turn-${invocation.role.asString}-follow-up'
              : 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: isFollowUp
              ? '${invocation.role.asString} follow-up response'
              : '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
          whiteboardEntries: [
            if (!isFollowUp && invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'open-question-1',
                kind: AiSeminarWhiteboardKind.openQuestion,
                text: 'Which interpretation should the reader test next?',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e1'],
              ),
          ],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarCardComposerService(List<String> prompts) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e1',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'The source passage.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      prompts.add(invocation.prompt);
      final isFollowUp = invocation.prompt.contains('Reader intervention:');
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: isFollowUp
              ? 'turn-${invocation.role.asString}-follow-up'
              : 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: isFollowUp
              ? '${invocation.role.asString} follow-up response'
              : '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarCardDisagreementService(List<String> prompts) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e1',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'The source passage.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      prompts.add(invocation.prompt);
      final isFollowUp = invocation.prompt.contains('Reader intervention:');
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: isFollowUp
              ? 'turn-${invocation.role.asString}-follow-up'
              : 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: isFollowUp
              ? '${invocation.role.asString} follow-up response'
              : '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
          whiteboardEntries: [
            if (!isFollowUp && invocation.role == AiSeminarRole.critical)
              const AiSeminarWhiteboardEntry(
                id: 'disagreement-1',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Scope remains disputed.',
                role: AiSeminarRole.critical,
                evidenceRefIds: ['e1'],
              ),
          ],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarCardDisagreementRefreshService(
  List<String> prompts,
  List<String> evidenceFetches,
) {
  SourceRef sourceRef(String id) {
    return SourceRef(
      bookId: 7,
      href: 'Text/ch$id.xhtml',
      cfi: 'epubcfi(/6/$id)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/$id%29',
      sourceTextSnippet: 'The $id source passage.',
      sourceKind: SourceRefKind.currentBookRag,
    );
  }

  return AiSeminarRuntimeService(
    fetchEvidence: (_) async {
      final id = evidenceFetches.isEmpty ? 'e1' : 'e2';
      evidenceFetches.add(id);
      return AiSeminarEvidenceBundle(
        query: '这个概念怎么理解？',
        evidence: [
          AiSeminarEvidence(
            id: id,
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The $id source passage.',
            sourceRef: sourceRef(id),
          ),
        ],
      );
    },
    streamRole: (invocation, _) async* {
      prompts.add(invocation.prompt);
      final evidenceId = invocation.evidenceBundle.evidence.single.id;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}-$evidenceId',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText:
              '${invocation.role.asString} response using $evidenceId',
          evidenceRefIds: [evidenceId],
          whiteboardEntries: [
            if (evidenceId == 'e1' && invocation.role == AiSeminarRole.critical)
              const AiSeminarWhiteboardEntry(
                id: 'disagreement-1',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Scope remains disputed.',
                role: AiSeminarRole.critical,
                evidenceRefIds: ['e1'],
              ),
          ],
        ),
      );
    },
    now: () => 1000,
  );
}
