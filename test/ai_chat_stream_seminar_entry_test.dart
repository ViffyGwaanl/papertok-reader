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
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'AiChatStream no longer carries an inline Seminar panel render path',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains('_inlineSeminarVisible')));
      expect(source, isNot(contains('_buildInlineSeminarPanel')));
      expect(source, isNot(contains('_openInlineSeminarRuntimePage')));
      expect(source, isNot(contains('_syncInlineSeminarRunCard')));
      expect(source, isNot(contains('openInlineSeminar')));
      expect(source, isNot(contains('embedded: true')));
    },
  );

  test(
    'Choose style picker does not carry a Seminar skill config branch',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains("if (skill.id == 'seminar_mode')")));
    },
  );

  test(
    'Seminar chat run card does not jump to global Seminar settings',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains('AiSeminarConfigPage')));
      expect(source, isNot(contains('ai_seminar_config.dart')));
    },
  );

  test(
    'AI Chat skill localization does not expose the native Seminar marker',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains('aiSkillSeminarModeName')));
      expect(source, isNot(contains('aiSkillSeminarModeDesc')));
    },
  );

  test(
    'Seminar wait failure copy uses native wait wording',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, contains("zh: '未能等待角色'"));
      expect(source, contains("en: 'Could not wait for role'"));
      expect(source, contains("zh: '未能等待工具调用'"));
      expect(source, contains("en: 'Could not wait for tool call'"));
      expect(source, isNot(contains("zh: '未能刷新角色'")));
      expect(source, isNot(contains("en: 'Could not refresh role'")));
      expect(source, isNot(contains("zh: '未能刷新工具调用'")));
      expect(source, isNot(contains("en: 'Could not refresh tool call'")));
    },
  );

  test(
    'Seminar setup sheet copy does not describe a card or panel',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains('即将插入的研讨卡')));
      expect(source, isNot(contains('next Seminar card')));
      expect(source, isNot(contains('panel can continue')));
      expect(source, contains('即将开始的研讨'));
      expect(source, contains('next Seminar run'));
    },
  );

  test(
    'ready Seminar settings copy describes the current run, not a card',
    () {
      final source =
          File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

      expect(source, isNot(contains('只影响这张研讨卡')));
      expect(source, isNot(contains('Only this Seminar card changes')));
      expect(source, contains('只影响本次研讨'));
      expect(source, contains('Only this Seminar run changes'));
    },
  );

  testWidgets(
    'Add-to-Chat Seminar creates a native chat run card without opening panel',
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
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('开始研讨'), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'direct native Seminar opener creates a native chat run card',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-legacy-');
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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-native-direct',
      );
      await tester.pump(const Duration(milliseconds: 100));

      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/chapter.xhtml',
        cfi: 'epubcfi(/6/4)',
        sourceTextSnippet: 'Evidence-backed passage.',
        sourceKind: SourceRefKind.reader,
      );
      final chatState =
          tester.state<AiChatStreamState>(find.byType(AiChatStream));

      chatState.openNativeSeminarCard(
        question: '原生入口问题是什么？',
        sessionId: 'native-direct-seminar',
        bookId: 99,
        sourceRef: sourceRef,
        maxRounds: 3,
        includeVerifier: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('原生入口问题是什么？'), findsAtLeastNWidgets(1));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('开始研讨'), findsOneWidget);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      expect(card?.question, '原生入口问题是什么？');
      expect(card?.sessionId, 'native-direct-seminar');
      expect(card?.bookId, 7);
      expect(card?.sourceRef?.href, 'Text/chapter.xhtml');
      expect(card?.sourceRefCount, 1);
      expect(card?.maxRounds, 3);
      expect(card?.roleIds, [
        'critical',
        'supportive',
        'verifier',
        'synthesizer',
      ]);
    },
  );

  testWidgets(
    'ready Seminar card edits run rounds inline without opening panel',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-setup-');
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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-setup',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);
      final setupPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'seminar_run_setup',
      );
      expect(setupPart?.text, '问题：这个概念怎么理解？');
      expect(setupPart?.label, contains('轮次：2'));
      expect(find.text('本次设置'), findsOneWidget);
      expect(find.text('最多 2 轮'), findsOneWidget);
      expect(find.text('调整设置'), findsOneWidget);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      final roundsPlus = find.byKey(
        ValueKey('seminar-chat-card-rounds-plus-$sessionId'),
      );
      expect(roundsPlus, findsOneWidget);
      final plusButton = tester.widget<IconButton>(roundsPlus);
      expect(plusButton.onPressed, isNotNull);
      plusButton.onPressed?.call();
      await tester.pumpAndSettle();

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final updatedSetupPart = updatedCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'seminar_run_setup',
      );
      expect(updatedCard?.maxRounds, 3);
      expect(updatedSetupPart?.label, contains('轮次：3'));
      expect(find.text('最多 3 轮'), findsOneWidget);
    },
  );

  testWidgets(
    'ready Seminar card toggles roles inline for the started run',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-roles-');
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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-roles',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      final supportiveToggle = find.byKey(
        ValueKey('seminar-chat-card-role-supportive-$sessionId'),
      );
      expect(supportiveToggle, findsOneWidget);
      tester.widget<SwitchListTile>(supportiveToggle).onChanged?.call(false);
      await tester.pumpAndSettle();

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      expect(updatedCard?.roleIds, isNot(contains('supportive')));
      final supportiveProfile = updatedCard?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.supportive,
      );
      expect(supportiveProfile?.enabled, isFalse);
      expect(find.text('2 个角色'), findsOneWidget);

      final startButton = find.byKey(
        ValueKey('seminar-chat-card-start-$sessionId'),
      );
      expect(startButton, findsOneWidget);
      tester.widget<FilledButton>(startButton).onPressed?.call();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId!,
      );

      final completedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final roleIds = completedCard?.snapshot?.roleSummaries
          .map((summary) => summary.roleId)
          .toList(growable: false);
      expect(roleIds, isNot(contains('supportive')));
    },
  );

  testWidgets(
    'ready Seminar card edits role evidence scope inline for the started run',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-scopes-');
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
          evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
        ),
      ];

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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-scopes',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);
      expect(find.text('证据：当前书籍'), findsOneWidget);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      final libraryScope = find.byKey(
        ValueKey(
          'seminar-chat-card-role-critical-scope-library-$sessionId',
        ),
      );
      expect(libraryScope, findsOneWidget);
      final libraryScopeChip = find.descendant(
        of: libraryScope,
        matching: find.byType(FilterChip),
      );
      expect(libraryScopeChip, findsOneWidget);
      tester.widget<FilterChip>(libraryScopeChip).onSelected?.call(true);
      await tester.pumpAndSettle();

      for (final scope in const [
        AiSeminarEvidenceScope.notes,
        AiSeminarEvidenceScope.memory,
        AiSeminarEvidenceScope.conceptGraph,
      ]) {
        final scopeChipRoot = find.byKey(
          ValueKey(
            'seminar-chat-card-role-critical-scope-'
            '${scope.asString}-$sessionId',
          ),
        );
        expect(scopeChipRoot, findsOneWidget);
        final scopeChip = find.descendant(
          of: scopeChipRoot,
          matching: find.byType(FilterChip),
        );
        expect(scopeChip, findsOneWidget);
        tester.widget<FilterChip>(scopeChip).onSelected?.call(true);
        await tester.pumpAndSettle();
      }

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final criticalProfile = updatedCard?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.critical,
      );
      expect(updatedCard?.evidenceScopeIds, contains('library'));
      expect(updatedCard?.evidenceScopeIds, contains('notes'));
      expect(updatedCard?.evidenceScopeIds, contains('memory'));
      expect(updatedCard?.evidenceScopeIds, contains('concept-graph'));
      expect(
        criticalProfile?.evidenceScopes,
        const [
          AiSeminarEvidenceScope.currentBook,
          AiSeminarEvidenceScope.library,
          AiSeminarEvidenceScope.notes,
          AiSeminarEvidenceScope.memory,
          AiSeminarEvidenceScope.conceptGraph,
        ],
      );
      expect(find.text('证据：当前书籍、书库、笔记、记忆、概念图谱'), findsOneWidget);
      expect(
        Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.evidenceScopes,
        const [AiSeminarEvidenceScope.currentBook],
      );

      final startButton = find.byKey(
        ValueKey('seminar-chat-card-start-$sessionId'),
      );
      expect(startButton, findsOneWidget);
      tester.widget<FilledButton>(startButton).onPressed?.call();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId!,
      );

      final runtimeState =
          container.read(aiSeminarRuntimeScopedProvider(sessionId));
      expect(
        runtimeState.session?.scopes,
        contains(AiSeminarEvidenceScope.library),
      );
      expect(
        runtimeState.session?.scopes,
        contains(AiSeminarEvidenceScope.notes),
      );
      expect(
        runtimeState.session?.scopes,
        contains(AiSeminarEvidenceScope.memory),
      );
      expect(
        runtimeState.session?.scopes,
        contains(AiSeminarEvidenceScope.conceptGraph),
      );
    },
  );

  testWidgets(
    'ready Seminar card edits role prompt inline for the started run',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-prompt-');
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
      final prompts = <String>[];

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
          customPrompt: '全局旧提示词。',
        ),
      ];

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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-prompt',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      final promptField = find.byKey(
        ValueKey('seminar-chat-card-role-critical-prompt-$sessionId'),
      );
      expect(promptField, findsOneWidget);
      await tester.enterText(promptField, '只在本场先质疑概念边界。');
      await tester.pumpAndSettle();

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final criticalProfile = updatedCard?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.critical,
      );
      expect(criticalProfile?.customPrompt, '只在本场先质疑概念边界。');
      expect(
        Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.customPrompt,
        '全局旧提示词。',
      );

      final startButton = find.byKey(
        ValueKey('seminar-chat-card-start-$sessionId'),
      );
      expect(startButton, findsOneWidget);
      tester.widget<FilledButton>(startButton).onPressed?.call();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId!,
      );

      expect(prompts.first, contains('只在本场先质疑概念边界。'));
      expect(prompts.first, isNot(contains('全局旧提示词。')));
    },
  );

  testWidgets(
    'ready Seminar card edits question inline for the started run',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-question-');
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
      final startedQuestions = <String>[];

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
              _seminarQuestionCaptureService(startedQuestions),
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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-question',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '旧问题是什么？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      final questionField = find.byKey(
        ValueKey('seminar-chat-card-question-input-$sessionId'),
      );
      expect(questionField, findsOneWidget);
      await tester.enterText(questionField, '新的本次研讨问题是什么？');
      await tester.pumpAndSettle();

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      expect(updatedCard?.question, '新的本次研讨问题是什么？');

      final startButton = find.byKey(
        ValueKey('seminar-chat-card-start-$sessionId'),
      );
      expect(startButton, findsOneWidget);
      tester.widget<FilledButton>(startButton).onPressed?.call();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId!,
      );

      expect(startedQuestions, ['新的本次研讨问题是什么？']);
    },
  );

  testWidgets(
    'ready Seminar card edits role tool range inline for the started run',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-card-tools-');
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
      final prompts = <String>[];

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
          allowedToolIds: const ['semantic_search_current_book'],
        ),
      ];

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
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-card-tools',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final sessionId = card?.sessionId;
      expect(sessionId, isNotNull);
      expect(find.textContaining('只读工具：1 个'), findsOneWidget);

      await tester.tap(find.text('调整设置'));
      await tester.pumpAndSettle();
      expect(find.text('书内语义检索'), findsAtLeastNWidgets(1));
      expect(find.text('书库语义检索'), findsAtLeastNWidgets(1));
      expect(find.text('记忆搜索'), findsAtLeastNWidgets(1));
      expect(find.text('图谱检索'), findsAtLeastNWidgets(1));
      expect(find.text('semantic_search_current_book'), findsNothing);
      expect(find.text('semantic_search_library'), findsNothing);
      expect(find.text('memory_search'), findsNothing);
      expect(find.text('concept_graph_search'), findsNothing);

      final libraryTool = find.byKey(
        ValueKey(
          'seminar-chat-card-role-critical-tool-semantic_search_library-'
          '$sessionId',
        ),
      );
      expect(libraryTool, findsOneWidget);
      final libraryChip = find.descendant(
        of: libraryTool,
        matching: find.byType(FilterChip),
      );
      expect(libraryChip, findsOneWidget);
      tester.widget<FilterChip>(libraryChip).onSelected?.call(true);
      await tester.pumpAndSettle();
      final memoryTool = find.byKey(
        ValueKey(
          'seminar-chat-card-role-critical-tool-memory_search-'
          '$sessionId',
        ),
      );
      expect(memoryTool, findsOneWidget);
      final memoryChip = find.descendant(
        of: memoryTool,
        matching: find.byType(FilterChip),
      );
      expect(memoryChip, findsOneWidget);
      tester.widget<FilterChip>(memoryChip).onSelected?.call(true);
      await tester.pumpAndSettle();
      final conceptGraphTool = find.byKey(
        ValueKey(
          'seminar-chat-card-role-critical-tool-concept_graph_search-'
          '$sessionId',
        ),
      );
      expect(conceptGraphTool, findsOneWidget);
      final conceptGraphChip = find.descendant(
        of: conceptGraphTool,
        matching: find.byType(FilterChip),
      );
      expect(conceptGraphChip, findsOneWidget);
      tester.widget<FilterChip>(conceptGraphChip).onSelected?.call(true);
      await tester.pumpAndSettle();

      final updatedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final criticalProfile = updatedCard?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.critical,
      );
      expect(criticalProfile?.allowedToolIds, [
        'semantic_search_current_book',
        'semantic_search_library',
        'memory_search',
        'concept_graph_search',
      ]);
      expect(find.textContaining('只读工具：4 个'), findsOneWidget);
      expect(
        Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.allowedToolIds,
        const ['semantic_search_current_book'],
      );

      final startButton = find.byKey(
        ValueKey('seminar-chat-card-start-$sessionId'),
      );
      expect(startButton, findsOneWidget);
      tester.widget<FilledButton>(startButton).onPressed?.call();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId!,
      );

      expect(
        prompts.first,
        contains(
          'Allowed read-only tools: '
          'semantic_search_current_book, semantic_search_library, '
          'memory_search, concept_graph_search',
        ),
      );
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
      expect(
        find.byKey(
          const ValueKey('seminar-run-role-critical-scope-current-book'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('seminar-run-role-critical-scope-library')),
      );
      await tester.tap(
        find.byKey(const ValueKey('seminar-run-role-critical-scope-library')),
      );
      await tester.pump();
      await tester
          .ensureVisible(find.byKey(const ValueKey('seminar-run-start')));
      await tester.tap(find.byKey(const ValueKey('seminar-run-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('开始研讨'), findsOneWidget);
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final setupPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'seminar_run_setup',
      );
      final criticalProfile = card?.roleProfiles.firstWhere(
        (profile) => profile.role == AiSeminarRole.critical,
      );
      expect(card?.maxRounds, 4);
      expect(setupPart?.id, 'setup-${card?.sessionId}');
      expect(setupPart?.text, '问题：这个概念怎么理解？');
      expect(setupPart?.label, contains('角色：批判者、支持者、综合者'));
      expect(setupPart?.label, isNot(contains('critical')));
      expect(setupPart?.label, isNot(contains('supportive')));
      expect(setupPart?.label, isNot(contains('synthesizer')));
      expect(setupPart?.label, contains('证据：当前书籍'));
      expect(setupPart?.label, isNot(contains('current-book')));
      expect(setupPart?.label, contains('轮次：4'));
      expect(setupPart?.roleIds, [
        'critical',
        'supportive',
        'synthesizer',
      ]);
      expect(criticalProfile?.customPrompt, '请先指出反方证据缺口，再决定是否需要刷新证据。');
      expect(criticalProfile?.evidenceScopes,
          const [AiSeminarEvidenceScope.currentBook]);
      expect(
        Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.evidenceScopes,
        const [AiSeminarEvidenceScope.library],
      );
      expect(
        criticalProfile?.allowedToolIds,
        const ['semantic_search_current_book'],
      );
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'Choose style does not expose native Seminar as a prompt style',
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

      expect(
        find.text('研讨会模式'),
        findsNothing,
        reason: 'AI 研讨会应从 AI Chat 原生 + 入口启动，不应作为普通提示词风格出现。',
      );
      expect(
        find.text('研讨会设置'),
        findsNothing,
        reason: '研讨会配置入口保留在 Settings，不放进普通聊天风格选择器。',
      );
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card stays native when card body is tapped',
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
      final entry =
          _seminarCardHistoryEntry(useNativeTimelineMessagePartsOnly: true);
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('3 个角色'), findsOneWidget);
      expect(find.text('证据：当前书籍'), findsOneWidget);
      expect(find.text('写入需确认'), findsOneWidget);
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('Native stream evidence bundle.'), findsOneWidget);
      expect(find.text('角色观点'), findsNothing);
      expect(find.text('1 · 批判者'), findsOneWidget);
      expect(find.text('Native stream role turn.'), findsOneWidget);
      expect(find.text('Native stream director cue.'), findsOneWidget);
      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('Native stream synthesis.'), findsOneWidget);
      expect(
        find.byTooltip('研讨会设置'),
        findsNothing,
        reason:
            'A native Seminar chat message should not jump out to the global Seminar settings page.',
      );
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      expect(find.widgetWithText(TextButton, '重新生成'), findsNothing);
      expect(find.widgetWithText(TextButton, '复制'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '角色'));
      await tester.pumpAndSettle();

      expect(find.text('角色观点'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('Native stream role turn.'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-question-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card opens checkpoint details natively',
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('可从中断处继续'), findsOneWidget);
      expect(find.textContaining('已完成 1 个角色'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '断点详情'), findsOneWidget);
      expect(find.text('断点详情'), findsOneWidget);
      expect(find.text('恢复详情'), findsNothing);
      expect(find.text('断点状态'), findsNothing);

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
      expect(find.text('断点状态'), findsOneWidget);
      expect(find.text('已保存证据'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('OpenAI / gpt-test'), findsOneWidget);
      expect(find.text('继续研讨'), findsOneWidget);
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
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
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId,
      );
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
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
      expect(invokedRoles, [AiSeminarRole.supportive]);

      releaseFirstRole.complete();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: sessionId,
      );

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
    'native Seminar card completion updates persisted chat card snapshot',
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
      final entry = _seminarCardHistoryEntry(
        includeSnapshot: false,
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.critical,
            allowedToolIds: const [
              'semantic_search_current_book',
              'notes_search',
            ],
          ),
        ],
      );
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('证据快照'), findsNothing);
      expect(find.text('开始研讨'), findsOneWidget);

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'completed');
      expect(card?.sourceRefCount, 4);
      expect(card?.snapshot?.evidence, hasLength(4));
      expect(card?.snapshot?.toolCalls, hasLength(1));
      expect(card?.snapshot?.toolCalls.single.toolId,
          'semantic_search_current_book');
      expect(card?.snapshot?.toolCalls.single.query, '这个概念怎么理解？');
      expect(card?.snapshot?.toolCalls.single.resultCount, 5);
      expect(card?.snapshot?.toolCalls.single.roleIds, [
        'critical',
        'supportive',
        'synthesizer',
      ]);
      expect(
        card?.snapshot?.toolCalls.single.evidenceRefs.map((item) => item.id),
        ['e1', 'e2', 'e3', 'e4'],
      );
      final toolPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'tool_call' && part.agentRunId == null,
      );
      expect(toolPart?.toolId, 'semantic_search_current_book');
      expect(toolPart?.query, '这个概念怎么理解？');
      expect(toolPart?.resultCount, 5);
      expect(toolPart?.roleIds, [
        'critical',
        'supportive',
        'synthesizer',
      ]);
      final evidencePart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'evidence');
      expect(
        evidencePart?.evidenceRefs.map((item) => item.id),
        contains('e1'),
      );
      expect(
        evidencePart?.evidenceRefs.map((item) => item.snippet),
        contains('The source passage.'),
      );
      expect(card?.snapshot?.evidence.first.snippet, 'The source passage.');
      expect(
        card?.snapshot?.evidence.map((item) => item.snippet),
        isNot(contains('Unused source passage 5.')),
      );
      expect(card?.snapshot?.roleSummaries.first.summary, 'critical response');
      final rolePart = card?.snapshot?.messageParts.singleWhere(
          (part) => part.type == 'role_turn' && part.roleId == 'critical');
      final seminarSessionId = card?.sessionId ?? '';
      expect(seminarSessionId, isNotEmpty);
      expect(rolePart?.roleId, 'critical');
      expect(rolePart?.text, 'critical response');
      expect(rolePart?.agentRunId, '$seminarSessionId:role-critical-0');
      expect(rolePart?.parentRunId, seminarSessionId);
      expect(
        rolePart?.evidenceRefs.map((item) => item.id),
        contains('e1'),
      );
      final criticalRoleToolPart = card?.snapshot?.messageParts.singleWhere(
        (part) =>
            part.type == 'tool_call' &&
            part.agentRunId == '$seminarSessionId:role-critical-0',
      );
      expect(criticalRoleToolPart?.parentRunId, seminarSessionId);
      expect(criticalRoleToolPart?.toolId, 'semantic_search_current_book');
      expect(criticalRoleToolPart?.query, '这个概念怎么理解？');
      expect(criticalRoleToolPart?.resultCount, 5);
      expect(criticalRoleToolPart?.roleIds, ['critical']);
      expect(
        criticalRoleToolPart?.evidenceRefs.map((item) => item.id),
        contains('e1'),
      );
      expect(
        card?.snapshot?.messageParts
            .where((part) =>
                part.agentRunId == '$seminarSessionId:role-critical-0' &&
                part.toolId == 'notes_search')
            .toList(growable: false),
        isEmpty,
      );
      final synthesisPart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'synthesis');
      expect(synthesisPart?.text, 'synthesizer response');
      expect(synthesisPart?.agentRunId, seminarSessionId);
      expect(synthesisPart?.parentRunId, isNull);
      expect(
        synthesisPart?.evidenceRefs.map((item) => item.id),
        contains('e1'),
      );
      expect(card?.snapshot?.synthesisSummary, 'synthesizer response');
      expect(card?.snapshot?.disagreements, ['Scope remains disputed.']);
      final disagreement = card?.snapshot?.disagreementDetails.single;
      expect(disagreement?.text, 'Scope remains disputed.');
      expect(disagreement?.roleIds, ['critical']);
      expect(disagreement?.evidenceRefs.single.id, 'e1');
      expect(disagreement?.evidenceRefs.single.snippet, 'The source passage.');
      final disagreementPart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'disagreement');
      expect(disagreementPart?.text, 'Scope remains disputed.');
      expect(disagreementPart?.roleIds, ['critical']);
      expect(disagreementPart?.evidenceRefs.single.id, 'e1');
      final contradictionScanPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'contradiction_scan',
      );
      expect(contradictionScanPart?.label, 'disagreement');
      expect(contradictionScanPart?.text, 'Scope remains disputed.');
      expect(contradictionScanPart?.roleIds, ['critical']);
      expect(contradictionScanPart?.evidenceRefs.single.id, 'e1');
    },
  );

  testWidgets(
    'native Seminar completion preserves all generated disagreement scans',
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
              _seminarSnapshotService(includeMultipleDisagreements: true),
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final disagreementTexts = card?.snapshot?.disagreementDetails
          .map((detail) => detail.text)
          .toList(growable: false);
      expect(disagreementTexts, hasLength(5));
      expect(disagreementTexts, contains('Runtime disagreement 5.'));

      final disagreementParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'disagreement')
          .toList(growable: false);
      expect(disagreementParts, hasLength(5));
      expect(
        disagreementParts?.map((part) => part.text),
        contains('Runtime disagreement 5.'),
      );

      final contradictionScanParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'contradiction_scan')
          .toList(growable: false);
      expect(contradictionScanParts, hasLength(5));
      expect(
        contradictionScanParts?.map((part) => part.text),
        contains('Runtime disagreement 5.'),
      );
    },
  );

  testWidgets(
    'native Seminar restored snapshot preserves all generated rebuttals',
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
      final runtimeState =
          _seminarRuntimeStateWithMultipleGeneratedRebuttals(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
            '${Uri.encodeComponent(sessionId)}': jsonEncode(
          runtimeState.toJson(),
        ),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();

      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final rebuttalParts = card?.snapshot?.messageParts
                .where((part) => part.type == 'disagreement_rebuttal')
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        if (rebuttalParts.length == 5) break;
      }

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rebuttalParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'disagreement_rebuttal')
          .toList(growable: false);

      expect(rebuttalParts, hasLength(5));
      expect(
        rebuttalParts?.map((part) => part.text),
        contains('Runtime rebuttal 5.'),
      );
      expect(
        rebuttalParts?.map((part) => part.label),
        contains('Runtime disagreement target 5.'),
      );
    },
  );

  testWidgets(
    'native Seminar restored snapshot preserves all generated role turns',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final runtimeState =
          _seminarRuntimeStateWithMultipleGeneratedRoleTurns(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
            '${Uri.encodeComponent(sessionId)}': jsonEncode(
          runtimeState.toJson(),
        ),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();

      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final roleTurnParts = card?.snapshot?.messageParts
                .where((part) => part.type == 'role_turn')
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        if (roleTurnParts.length == 5) break;
      }

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final roleTurnParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'role_turn')
          .toList(growable: false);

      expect(roleTurnParts, hasLength(5));
      expect(
        roleTurnParts?.map((part) => part.text),
        contains('Runtime role response 5.'),
      );

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-roles-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('Runtime role response 5.'), findsOneWidget);
    },
  );

  testWidgets(
    'native Seminar restored snapshot preserves all generated evidence',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final runtimeState =
          _seminarRuntimeStateWithMultipleGeneratedEvidence(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
            '${Uri.encodeComponent(sessionId)}': jsonEncode(
          runtimeState.toJson(),
        ),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();

      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final evidenceRefs = card?.snapshot?.messageParts
                .where((part) => part.type == 'evidence')
                .expand((part) => part.evidenceRefs)
                .toList(growable: false) ??
            const <AiSeminarRunCardEvidenceSnapshot>[];
        if (evidenceRefs.length == 5) break;
      }

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final evidenceRefs = card?.snapshot?.messageParts
          .where((part) => part.type == 'evidence')
          .expand((part) => part.evidenceRefs)
          .toList(growable: false);

      expect(card?.snapshot?.evidence, hasLength(5));
      expect(evidenceRefs, hasLength(5));
      expect(
        evidenceRefs?.map((item) => item.snippet),
        contains('Runtime evidence 5.'),
      );

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-evidence-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('Runtime evidence 5.'), findsOneWidget);
    },
  );

  testWidgets(
    'native Seminar restored snapshot preserves all generated evidence tool calls',
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
      final runtimeState =
          _seminarRuntimeStateWithMultipleGeneratedToolCalls(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
            '${Uri.encodeComponent(sessionId)}': jsonEncode(
          runtimeState.toJson(),
        ),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();

      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final toolCallParts = card?.snapshot?.messageParts
                .where((part) => part.type == 'tool_call')
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        if (toolCallParts.length == 6) break;
      }

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final toolCallParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'tool_call')
          .toList(growable: false);

      expect(card?.snapshot?.toolCalls, hasLength(6));
      expect(toolCallParts, hasLength(6));
      expect(
        toolCallParts?.map((part) => part.id),
        contains('evidence-concept-graph'),
      );
      expect(
        toolCallParts?.map((part) => part.toolId),
        contains('concept_graph_search'),
      );
    },
  );

  testWidgets(
    'native Seminar completion preserves all role evidence refs in message parts',
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
              _seminarSnapshotService(
                criticalEvidenceRefIds: const ['e1', 'e2', 'e3'],
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rolePart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'role_turn' && part.roleId == 'critical',
      );

      expect(rolePart?.evidenceRefs.map((item) => item.id), [
        'e1',
        'e2',
        'e3',
      ]);
      expect(rolePart?.evidenceRefs.map((item) => item.snippet), [
        'The source passage.',
        'Additional source passage 2.',
        'Additional source passage 3.',
      ]);
    },
  );

  testWidgets(
    'native Seminar card marks tool calls with role evidence visibility',
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
              _seminarScopedToolCallService(),
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              includeSnapshot: false,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  evidenceScopes: const [
                    AiSeminarEvidenceScope.currentBook,
                    AiSeminarEvidenceScope.memory,
                  ],
                ),
                AiSeminarRoleProfile(
                  role: AiSeminarRole.supportive,
                  evidenceScopes: const [
                    AiSeminarEvidenceScope.library,
                    AiSeminarEvidenceScope.conceptGraph,
                  ],
                ),
                AiSeminarRoleProfile(
                  role: AiSeminarRole.synthesizer,
                  enabled: false,
                ),
              ],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final toolParts = card?.snapshot?.messageParts
              .where((part) => part.type == 'tool_call')
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      final currentBookPart = toolParts.singleWhere(
        (part) => part.toolId == 'semantic_search_current_book',
      );
      final libraryPart = toolParts.singleWhere(
        (part) => part.toolId == 'semantic_search_library',
      );
      final memoryPart = toolParts.singleWhere(
        (part) => part.toolId == 'memory_search',
      );
      final conceptGraphPart = toolParts.singleWhere(
        (part) => part.toolId == 'concept_graph_search',
      );
      expect(currentBookPart.roleIds, ['critical']);
      expect(libraryPart.roleIds, ['supportive']);
      expect(memoryPart.roleIds, ['critical']);
      expect(conceptGraphPart.roleIds, ['supportive']);
    },
  );

  testWidgets(
    'Seminar chat card starts a ready run without opening the panel',
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
      container
          .read(aiChatProvider.notifier)
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('开始研讨'), findsOneWidget);

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'completed');
      expect(
        card?.snapshot?.messageParts.any(
          (part) =>
              part.type == 'seminar_run_setup' && part.text == '问题：这个概念怎么理解？',
        ),
        isTrue,
      );
      expect(card?.snapshot?.roleSummaries.first.summary, 'critical response');
      expect(find.text('研讨流'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card persists Director refreshEvidence message parts',
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
              _seminarNeedsEvidenceService(),
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
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(runtimeState.status, AiSeminarRunStatus.needsEvidence);
      expect(
        runtimeState.directorState!.nextIntent,
        AiSeminarDirectorNextIntent.refreshEvidence,
      );
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('主持人准备重新找证据'), findsOneWidget);
      expect(
        find.text('AI Seminar requires traceable current-source evidence.'),
        findsOneWidget,
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'needs-evidence');
      final directorPart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'director_state');
      expect(directorPart?.id, 'director-seminar-chat-history');
      expect(directorPart?.label, 'refresh-evidence');
      expect(
        directorPart?.text,
        'AI Seminar requires traceable current-source evidence.',
      );
    },
  );

  testWidgets(
    'Seminar chat card renders failed runtime as native Director state',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-failed-retry-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      container
          .read(
            aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
          )
          .restore(AiSeminarRuntimeState.initial().copyWith(
            session: AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              sourceRefs: [
                SourceRef(
                  bookId: 7,
                  href: 'Text/ch1.xhtml',
                  cfi: 'epubcfi(/6/8)',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                  sourceTextSnippet: 'The source passage.',
                  sourceKind: SourceRefKind.currentBookRag,
                ),
              ],
            ),
            status: AiSeminarRunStatus.failed,
            error:
                'No pending AI Seminar agent control is available to process.',
            backgroundJob: const AiSeminarBackgroundJobSnapshot(
              id: 'job-stale-control',
              sessionId: 'seminar-chat-history',
              status: AiSeminarBackgroundJobStatus.failed,
              startedAt: 900,
              updatedAt: 901,
              completedAt: 901,
              message:
                  'No pending AI Seminar agent control is available to process.',
            ),
            backgroundJobs: const [
              AiSeminarBackgroundJobSnapshot(
                id: 'job-stale-control',
                sessionId: 'seminar-chat-history',
                status: AiSeminarBackgroundJobStatus.failed,
                startedAt: 900,
                updatedAt: 901,
                completedAt: 901,
                message:
                    'No pending AI Seminar agent control is available to process.',
              ),
            ],
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('研讨运行失败'), findsOneWidget);
      expect(find.text('重新生成角色'), findsOneWidget);
      expect(
        find.text(
          'No pending AI Seminar agent control is available to process.',
        ),
        findsOneWidget,
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'failed');
      final directorPart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'director_state');
      expect(directorPart?.id, 'director-seminar-chat-history:failed');
      expect(directorPart?.label, 'failed');
      expect(directorPart?.status, 'failed');
      expect(directorPart?.actionIds, ['retry-agent-control']);
      expect(
        directorPart?.text,
        'No pending AI Seminar agent control is available to process.',
      );

      final retryAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-retry-agent-control-'
          'seminar-chat-history',
        ),
      );
      expect(retryAction, findsOneWidget);
      final retryChip = tester.widget<ActionChip>(retryAction);
      expect(retryChip.onPressed, isNotNull);
      await tester.runAsync(() async {
        retryChip.onPressed?.call();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final retriedState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(
        retriedState.status,
        AiSeminarRunStatus.completed,
        reason:
            'error=${retriedState.error}; canRetry=${retriedState.canRetry}',
      );
      final retriedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(retriedCard?.status, 'completed');
      expect(find.text('critical response'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card marks active child control as processing inline',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-control-processing-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      container
          .read(
            aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
          )
          .restore(AiSeminarRuntimeState.initial().copyWith(
            session: AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              sourceRefs: [
                SourceRef(
                  bookId: 7,
                  href: 'Text/ch1.xhtml',
                  cfi: 'epubcfi(/6/8)',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                  sourceTextSnippet: 'The source passage.',
                  sourceKind: SourceRefKind.currentBookRag,
                ),
              ],
            ),
            status: AiSeminarRunStatus.running,
            activeRole: AiSeminarRole.critical,
            evidenceBundle: AiSeminarEvidenceBundle(
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
                    jumpLink:
                        'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                    sourceTextSnippet: 'The source passage.',
                    sourceKind: SourceRefKind.currentBookRag,
                  ),
                ),
              ],
            ),
            directorState: const AiSeminarDirectorState(
              sessionId: 'seminar-chat-history',
              nextIntent: AiSeminarDirectorNextIntent.runRole,
              lastUserIntervention: AiSeminarUserIntervention(
                id: 'seminar-chat-history:role-critical-0:retry-request:1200',
                text: 'Retry requested.',
                requestedAction: AiSeminarUserInterventionAction.askRole,
                targetRole: AiSeminarRole.critical,
                createdAt: 1200,
              ),
            ),
            startedAt: 900,
            backgroundJob: const AiSeminarBackgroundJobSnapshot(
              id: 'job-control-processing',
              sessionId: 'seminar-chat-history',
              status: AiSeminarBackgroundJobStatus.running,
              startedAt: 900,
              updatedAt: 901,
            ),
            backgroundJobs: const [
              AiSeminarBackgroundJobSnapshot(
                id: 'job-control-processing',
                sessionId: 'seminar-chat-history',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
            ],
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Retry requested.'), findsNothing);
      expect(find.text('处理中'), findsOneWidget);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final readerPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'reader_turn' && part.roleId == 'critical',
      );
      expect(readerPart?.label, 'retry-agent-control');
      expect(readerPart?.status, 'running');
      expect(readerPart?.text, isNull);
      expect(
        readerPart?.agentRunId,
        'seminar-chat-history:role-critical-0',
      );
      expect(readerPart?.parentRunId, 'seminar-chat-history');
    },
  );

  testWidgets(
    'Seminar chat card marks accepted child control as processing before role starts',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-control-accepted-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      container
          .read(
            aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
          )
          .restore(AiSeminarRuntimeState.initial().copyWith(
            session: AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              sourceRefs: [
                SourceRef(
                  bookId: 7,
                  href: 'Text/ch1.xhtml',
                  cfi: 'epubcfi(/6/8)',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                  sourceTextSnippet: 'The source passage.',
                  sourceKind: SourceRefKind.currentBookRag,
                ),
              ],
            ),
            status: AiSeminarRunStatus.running,
            activeAgentControlRunId: 'seminar-chat-history:role-critical-0',
            evidenceBundle: AiSeminarEvidenceBundle(
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
                    jumpLink:
                        'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                    sourceTextSnippet: 'The source passage.',
                    sourceKind: SourceRefKind.currentBookRag,
                  ),
                ),
              ],
            ),
            directorState: const AiSeminarDirectorState(
              sessionId: 'seminar-chat-history',
              nextIntent: AiSeminarDirectorNextIntent.runRole,
              lastUserIntervention: AiSeminarUserIntervention(
                id: 'seminar-chat-history:role-critical-0:resume-request:1200',
                text: 'Resume requested.',
                requestedAction: AiSeminarUserInterventionAction.askRole,
                targetRole: AiSeminarRole.critical,
                createdAt: 1200,
              ),
            ),
            startedAt: 900,
            backgroundJob: const AiSeminarBackgroundJobSnapshot(
              id: 'job-control-accepted',
              sessionId: 'seminar-chat-history',
              status: AiSeminarBackgroundJobStatus.running,
              startedAt: 900,
              updatedAt: 901,
            ),
            backgroundJobs: const [
              AiSeminarBackgroundJobSnapshot(
                id: 'job-control-accepted',
                sessionId: 'seminar-chat-history',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
            ],
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Resume requested.'), findsNothing);
      expect(find.text('处理中'), findsOneWidget);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final readerPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'reader_turn' && part.roleId == 'critical',
      );
      expect(readerPart?.label, 'resume-agent');
      expect(readerPart?.status, 'running');
      expect(readerPart?.text, isNull);
      expect(
        readerPart?.agentRunId,
        'seminar-chat-history:role-critical-0',
      );
      expect(readerPart?.parentRunId, 'seminar-chat-history');
    },
  );

  testWidgets(
    'Seminar chat card does not mark stale child control as processing',
    (tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-stale-control-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
          .loadHistoryEntry(_seminarCardHistoryEntry(includeSnapshot: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      container
          .read(
            aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
          )
          .restore(AiSeminarRuntimeState.initial().copyWith(
            session: AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              sourceRefs: [
                SourceRef(
                  bookId: 7,
                  href: 'Text/ch1.xhtml',
                  cfi: 'epubcfi(/6/8)',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                  sourceTextSnippet: 'The source passage.',
                  sourceKind: SourceRefKind.currentBookRag,
                ),
              ],
            ),
            status: AiSeminarRunStatus.running,
            evidenceBundle: AiSeminarEvidenceBundle(
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
                    jumpLink:
                        'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                    sourceTextSnippet: 'The source passage.',
                    sourceKind: SourceRefKind.currentBookRag,
                  ),
                ),
              ],
            ),
            directorState: const AiSeminarDirectorState(
              sessionId: 'seminar-chat-history',
              nextIntent: AiSeminarDirectorNextIntent.refreshEvidence,
              lastUserIntervention: AiSeminarUserIntervention(
                id: 'seminar-chat-history:role-critical-0:resume-request:1200',
                text: 'Old resume request.',
                requestedAction: AiSeminarUserInterventionAction.askRole,
                targetRole: AiSeminarRole.critical,
                createdAt: 1200,
              ),
            ),
            startedAt: 900,
            backgroundJob: const AiSeminarBackgroundJobSnapshot(
              id: 'job-normal-running',
              sessionId: 'seminar-chat-history',
              status: AiSeminarBackgroundJobStatus.running,
              startedAt: 900,
              updatedAt: 901,
            ),
            backgroundJobs: const [
              AiSeminarBackgroundJobSnapshot(
                id: 'job-normal-running',
                sessionId: 'seminar-chat-history',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
            ],
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('Old resume request.'), findsOneWidget);
      expect(find.text('处理中'), findsNothing);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final readerPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'reader_turn' && part.roleId == 'critical',
      );
      expect(readerPart?.label, 'resume-agent');
      expect(readerPart?.status, isNull);
      expect(
        readerPart?.agentRunId,
        'seminar-chat-history:role-critical-0',
      );
      expect(readerPart?.parentRunId, 'seminar-chat-history');
    },
  );

  testWidgets(
    'Seminar chat card does not restart a card that already has a snapshot',
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
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('开始研讨'), findsNothing);
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
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-whiteboard-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
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
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('1 · 批判者'), findsOneWidget);
      expect(find.text('2 · 支持者'), findsOneWidget);
      expect(find.text('本轮证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsWidgets);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders role turn message parts',
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
            _seminarCardHistoryEntry(useRoleMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('1 · 批判者'), findsOneWidget);
      expect(
          find.text('This claim needs a boundary condition.'), findsOneWidget);
      expect(find.text('本轮证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsWidgets);
    },
  );

  testWidgets(
    'persisted Seminar role turn shows all linked evidence sources',
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
              useRoleMessagePartsOnly: true,
              useRoleMultipleEvidenceRefs: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('本轮证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
      expect(find.text('Second role evidence.'), findsOneWidget);
      expect(find.text('Third role evidence.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders role partial message parts',
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
            _seminarCardHistoryEntry(useRolePartialMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('角色发言生成中'), findsOneWidget);
      expect(
        find.text('Streaming role partial from message part.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all role partial message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
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
              useLegacyMultipleRolePartialMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('Role partial 1.'), findsOneWidget);
      expect(find.text('Role partial 4.'), findsOneWidget);
      expect(
        find.text('Role partial 5 should stay visible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all role turn message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
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
              useLegacyMultipleRoleTurnMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨时间线'), findsOneWidget);
      expect(find.text('Role turn 1.'), findsOneWidget);
      expect(find.text('Role turn 4.'), findsOneWidget);
      expect(
        find.text('Role turn 5 should stay visible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card renders evidence message parts',
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
            _seminarCardHistoryEntry(useEvidenceMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Evidence part snippet.'), findsOneWidget);
      expect(find.text('来源缺失'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar evidence block shows all evidence refs',
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
              useEvidenceMessagePartsOnly: true,
              useEvidenceMultipleRefs: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Evidence part snippet.'), findsOneWidget);
      expect(find.text('Second evidence part snippet.'), findsOneWidget);
      expect(find.text('Third evidence part snippet.'), findsOneWidget);
      expect(find.text('Fourth evidence part snippet.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar evidence tab shows all snapshot evidence',
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
              useSnapshotMultipleEvidenceRefs: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-evidence-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('Second snapshot evidence.'), findsOneWidget);
      expect(find.text('Third snapshot evidence.'), findsOneWidget);
      expect(find.text('Fourth snapshot evidence.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders evidence bundle message parts',
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
              useEvidenceMessagePartsOnly: true,
              useEvidenceBundleMessagePartType: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Evidence part snippet.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders reader turn message parts',
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
            _seminarCardHistoryEntry(useReaderTurnMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('读者参与'), findsNothing);
      expect(find.text('已处理'), findsOneWidget);
      expect(find.textContaining('处理时间'), findsOneWidget);
      expect(find.text('Reader turn part text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar tool wait reader turn shows tool context',
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
              useToolWaitReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('等待工具调用 · 批判者'), findsOneWidget);
      expect(find.text('工具：笔记搜索'), findsOneWidget);
      expect(find.text('查询：agency notes'), findsOneWidget);
      expect(find.text('待处理'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all reader turn message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
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
              useLegacyMultipleReaderTurnMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('读者参与'), findsOneWidget);
      expect(find.text('Reader control 1.'), findsOneWidget);
      expect(find.text('Reader control 4.'), findsOneWidget);
      expect(
        find.text('Reader control 5 should stay visible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card marks pending reader control parts',
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
              usePendingReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('待处理'), findsOneWidget);
      expect(find.text('Pending reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders pendingInit reader control as processing',
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
              usePendingInitReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('处理中'), findsOneWidget);
      expect(find.textContaining('发送输入'), findsOneWidget);
      expect(find.textContaining('批判者'), findsOneWidget);
      expect(find.text('Pending init reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card marks cancelled reader control parts',
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
              useCancelledReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.textContaining('取消时间'), findsOneWidget);
      expect(find.textContaining('处理时间'), findsNothing);
      expect(find.text('Cancelled reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card treats canceled reader controls as cancelled',
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
              useCancelledReaderTurnMessagePartsOnly: true,
              cancelledReaderTurnStatus: 'canceled',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.textContaining('取消时间'), findsOneWidget);
      expect(find.textContaining('处理时间'), findsNothing);
      expect(find.text('Cancelled reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card labels pending retry reader control parts',
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
              usePendingRetryReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('待处理'), findsOneWidget);
      expect(find.textContaining('重新生成角色'), findsOneWidget);
      expect(find.text('Retry reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card labels pending wait reader control parts',
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
              usePendingWaitReaderTurnMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('待处理'), findsOneWidget);
      expect(find.textContaining('等待角色'), findsOneWidget);
      expect(find.text('Wait reader control text.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders Director askUser message parts',
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
              useDirectorStateMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('主持人正在等待你的回应'), findsOneWidget);
      expect(
        find.text('Which interpretation should the reader test next?'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('seminar-chat-card-reply-seminar-chat-history'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'persisted Seminar Director state only card exposes status tab',
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
              useDirectorStateMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-status-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('状态详情'), findsOneWidget);
      expect(find.text('主持人正在等待你的回应'), findsOneWidget);
      expect(
        find.text('Which interpretation should the reader test next?'),
        findsOneWidget,
      );
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('Agent trace'), findsNothing);
      expect(find.text('seminar-chat-history'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all director state message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
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
              useLegacyMultipleDirectorStateMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('主持人下一步'), findsOneWidget);
      expect(find.text('Director cue 1.'), findsOneWidget);
      expect(find.text('Director cue 3.'), findsOneWidget);
      expect(
        find.text('Director cue 4 should stay visible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card renders interrupted Director state',
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
              useDirectorStateMessagePartsOnly: true,
              directorStateLabel: 'interrupted',
              directorStateText: 'Checkpoint was interrupted.',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('研讨已中断'), findsOneWidget);
      expect(find.text('Checkpoint was interrupted.'), findsOneWidget);
      expect(find.text('角色生成已中断'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders running Director state',
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
              useDirectorStateMessagePartsOnly: true,
              directorStateLabel: 'running',
              directorStateText: 'Director is running.',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('研讨正在运行'), findsOneWidget);
      expect(find.text('Director is running.'), findsOneWidget);
      expect(find.text('角色正在生成'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders stopped Director state',
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
              useDirectorStateMessagePartsOnly: true,
              directorStateLabel: 'stopped',
              directorStateText: 'Director was shut down.',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('研讨已停止'), findsOneWidget);
      expect(find.text('Director was shut down.'), findsOneWidget);
      expect(find.text('角色生成已停止'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders missing Director state',
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
              useDirectorStateMessagePartsOnly: true,
              directorStateLabel: 'not-found',
              directorStateText: 'Director was not found.',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('研讨运行未找到'), findsOneWidget);
      expect(find.text('Director was not found.'), findsOneWidget);
      expect(find.text('角色运行未找到'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders role running agent status parts',
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
              useRoleStatusMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('角色正在生成'), findsOneWidget);
      expect(find.text('Critical is running.'), findsOneWidget);
      expect(find.text('可用控制'), findsOneWidget);
      expect(find.text('等待角色'), findsOneWidget);
      expect(find.text('停止角色'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card uses agent metadata for status controls',
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
              useRoleStatusAgentMetadataOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('角色正在生成'), findsOneWidget);
      expect(find.text('Critical is running.'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-wait-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-close-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card renders native agent status parts',
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
              useAgentStatusMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final statusPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'agent_status',
      );
      expect(statusPart?.allowedToolIds, [
        'semantic_search_current_book',
        'notes_search',
      ]);
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('角色正在生成'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('critical'), findsNothing);
      expect(find.text('Critical is running.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:role-critical-0'), findsOneWidget);
      expect(find.text('允许工具'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('笔记搜索'), findsAtLeastNWidgets(1));
      expect(find.text('semantic_search_current_book'), findsNothing);
      expect(find.text('notes_search'), findsNothing);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-wait-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar terminal agent controls are historical',
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
              useAgentStatusMessagePartsOnly: true,
              agentStatusLabel: 'role-completed',
              agentStatusText: 'Critical completed.',
              agentStatusActionIds: const ['wait-agent', 'close-agent'],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('角色已完成'), findsOneWidget);
      expect(find.text('Critical completed.'), findsOneWidget);
      expect(find.text('历史控制'), findsOneWidget);
      expect(find.text('可用控制'), findsNothing);
      expect(find.text('等待角色'), findsOneWidget);
      expect(find.text('停止角色'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-wait-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-close-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'persisted Seminar control only card exposes controls tab',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useAgentStatusMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-controls-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('控制详情'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('角色正在生成'), findsOneWidget);
      expect(find.text('Critical is running.'), findsOneWidget);
      expect(find.text('可用控制'), findsOneWidget);
      expect(find.text('等待角色'), findsOneWidget);
      expect(find.text('停止角色'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:role-critical-0'), findsOneWidget);
    },
  );

  testWidgets(
    'reading Seminar agent status hides library fallback tools',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useAgentStatusMessagePartsOnly: true,
              agentStatusAllowedToolIds: const [
                'semantic_search_current_book',
                'semantic_search_library',
              ],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final statusPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'agent_status',
      );
      expect(statusPart?.allowedToolIds, [
        'semantic_search_current_book',
        'semantic_search_library',
      ]);
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('角色状态'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('critical'), findsNothing);
      expect(find.text('允许工具'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('semantic_search_current_book'), findsNothing);
      expect(find.text('semantic_search_library'), findsNothing);
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all agent status message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useLegacyMultipleAgentStatusMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('角色状态'), findsWidgets);
      expect(find.text('Agent status 4 should stay visible.'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-send-input-'
            'seminar-chat-history:role-critical-3',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card stops an open role agent from native controls',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-stop-agent-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final startedAt = DateTime.utc(2026, 6, 4, 17, 30);
      final graphStore = AgentRunGraphStore();
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
      });

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
              useRoleStatusMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final closeAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-close-agent-'
          'seminar-chat-history:role-critical-0',
        ),
      );
      expect(closeAction, findsOneWidget);

      final closeChip = tester.widget<ActionChip>(closeAction);
      await tester.runAsync(() async {
        closeChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      List<AgentRunGraphEntry>? openChildren;
      await tester.runAsync(() async {
        openChildren = await graphStore.listOpenChildren(
          'seminar-chat-history',
        );
      });
      expect(openChildren, isEmpty);
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final criticalStatusLabels = card?.snapshot?.messageParts
          .where(
            (part) => part.type == 'agent_status' && part.roleId == 'critical',
          )
          .map((part) => part.label)
          .toList(growable: false);
      expect(criticalStatusLabels, ['role-shutdown']);
      expect(find.text('角色生成已停止'), findsOneWidget);
      expect(find.text('停止角色'), findsNothing);
    },
  );

  testWidgets(
    'Seminar chat card stops active child control runtime natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-stop-active-control-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final startedAt = DateTime.utc(2026, 6, 5, 11);
      final graphStore = AgentRunGraphStore();
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
      });

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
              useRoleStatusMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final closeAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-close-agent-'
          'seminar-chat-history:role-critical-0',
        ),
      );
      expect(closeAction, findsOneWidget);
      final closeChip = tester.widget<ActionChip>(closeAction);

      container
          .read(
            aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
          )
          .restore(AiSeminarRuntimeState.initial().copyWith(
            session: AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              sourceRefs: [
                SourceRef(
                  bookId: 7,
                  href: 'Text/ch1.xhtml',
                  cfi: 'epubcfi(/6/8)',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                  sourceTextSnippet: 'The source passage.',
                  sourceKind: SourceRefKind.currentBookRag,
                ),
              ],
            ),
            status: AiSeminarRunStatus.running,
            activeAgentControlRunId: 'seminar-chat-history:role-critical-0',
            evidenceBundle: AiSeminarEvidenceBundle(
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
                    jumpLink:
                        'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                    sourceTextSnippet: 'The source passage.',
                    sourceKind: SourceRefKind.currentBookRag,
                  ),
                ),
              ],
            ),
            startedAt: 900,
            backgroundJob: const AiSeminarBackgroundJobSnapshot(
              id: 'job-active-control-close',
              sessionId: 'seminar-chat-history',
              status: AiSeminarBackgroundJobStatus.running,
              startedAt: 900,
              updatedAt: 901,
            ),
            backgroundJobs: const [
              AiSeminarBackgroundJobSnapshot(
                id: 'job-active-control-close',
                sessionId: 'seminar-chat-history',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
            ],
          ));

      await tester.runAsync(() async {
        closeChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(runtimeState.status, AiSeminarRunStatus.cancelled);
      expect(runtimeState.activeAgentControlRunId, isNull);
      expect(runtimeState.backgroundJob?.status,
          AiSeminarBackgroundJobStatus.cancelled);

      List<AgentRunGraphEntry>? openChildren;
      await tester.runAsync(() async {
        openChildren = await graphStore.listOpenChildren(
          'seminar-chat-history',
        );
      });
      expect(openChildren, isEmpty);
    },
  );

  testWidgets(
    'Seminar chat card waits for a child agent and refreshes graph result',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-wait-agent-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
      await tester.runAsync(() async {
        await container.read(aiChatProvider.future);
        container.read(aiChatProvider.notifier).restore(
          [ChatMessage.humanText('已有会话')],
          sessionId: 'session-seminar-wait-agent-widget',
        );
        await container.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: '这个概念怎么理解？',
              bookId: 7,
              seminarSessionId: 'seminar-chat-wait-agent-widget',
            );
        await container
            .read(aiChatProvider.notifier)
            .updateSeminarRunCardSnapshot(
              seminarSessionId: 'seminar-chat-wait-agent-widget',
              status: 'running',
              snapshot: const AiSeminarRunCardSnapshot(
                messageParts: [
                  AiSeminarRunCardMessagePart(
                    type: 'director_state',
                    id: 'seminar-chat-wait-agent-widget:role-critical-0:status:running',
                    roleId: 'critical',
                    label: 'role-running',
                    text: 'Critical is running.',
                    actionIds: ['wait-agent', 'close-agent'],
                  ),
                ],
              ),
            );
      });

      final startedAt = DateTime.utc(2026, 6, 4, 18, 30);
      final graphStore = AgentRunGraphStore();
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-wait-agent-widget',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-wait-agent-widget:role-critical-0',
          parentRunId: 'seminar-chat-wait-agent-widget',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.completed,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
          finishedAt: startedAt.add(const Duration(seconds: 4)),
          result: 'Critical result from widget graph.',
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final waitAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-wait-agent-'
          'seminar-chat-wait-agent-widget:role-critical-0',
        ),
      );
      expect(waitAction, findsOneWidget);

      final waitChip = tester.widget<ActionChip>(waitAction);
      await tester.runAsync(() async {
        waitChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final criticalStatusLabels = card?.snapshot?.messageParts
          .where(
            (part) => part.type == 'agent_status' && part.roleId == 'critical',
          )
          .map((part) => part.label)
          .toList(growable: false);

      expect(criticalStatusLabels, ['role-completed']);
      expect(find.text('角色已完成'), findsOneWidget);
      expect(find.text('Critical result from widget graph.'), findsOneWidget);
      expect(find.text('等待角色'), findsNothing);
    },
  );

  testWidgets(
    'Seminar chat card sends input to a waiting child agent natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-send-input-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final graphStore = AgentRunGraphStore();
      final prompts = <String>[];
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final evidenceBundle = AiSeminarEvidenceBundle(
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
      final runtimeSession = AiSeminarSessionContract(
        id: 'seminar-chat-send-input-widget',
        question: '这个概念怎么理解？',
        bookId: 7,
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.synthesizer,
            enabled: false,
          ),
        ],
      );
      final runtimeService = AiSeminarRuntimeService(
        fetchEvidence: (_) => fail('active runtime should reuse evidence'),
        streamRole: (invocation, _) async* {
          prompts.add(invocation.prompt);
          yield AiSeminarRoleStreamChunk(
            completedTurn: AiSeminarRoleTurn(
              id: 'turn-control-critical',
              role: invocation.role,
              prompt: invocation.prompt,
              responseText: 'critical control response',
              evidenceRefIds: const ['e1'],
            ),
          );
        },
        agentRunGraphStore: graphStore,
        now: () => 1500,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
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
      await tester.runAsync(() async {
        await container.read(aiChatProvider.future);
        container.read(aiChatProvider.notifier).restore(
          [ChatMessage.humanText('已有会话')],
          sessionId: 'session-seminar-send-input-widget',
        );
        await container.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: '这个概念怎么理解？',
              bookId: 7,
              seminarSessionId: 'seminar-chat-send-input-widget',
            );
        await container
            .read(aiChatProvider.notifier)
            .updateSeminarRunCardSnapshot(
              seminarSessionId: 'seminar-chat-send-input-widget',
              status: 'running',
              snapshot: const AiSeminarRunCardSnapshot(
                messageParts: [
                  AiSeminarRunCardMessagePart(
                    type: 'director_state',
                    id: 'seminar-chat-send-input-widget:role-critical-0:status:waiting_input',
                    roleId: 'critical',
                    label: 'role-waiting-input',
                    text: 'Critical is waiting for input.',
                    actionIds: ['send-input', 'close-agent'],
                  ),
                ],
              ),
            );
      });

      final startedAt = DateTime.utc(2026, 6, 4, 19, 30);
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-send-input-widget',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-send-input-widget:role-critical-0',
          parentRunId: 'seminar-chat-send-input-widget',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.waitingInput,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final sendAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-send-input-'
          'seminar-chat-send-input-widget:role-critical-0',
        ),
      );
      expect(sendAction, findsOneWidget);

      final sendChip = tester.widget<ActionChip>(sendAction);
      sendChip.onPressed?.call();
      await tester.pump();

      final input = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-input-'
          'seminar-chat-send-input-widget:role-critical-0',
        ),
      );
      expect(input, findsOneWidget);
      await tester.enterText(input, '请先解释还缺哪条原文证据。');
      await tester.pump();

      final submit = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-input-submit-'
          'seminar-chat-send-input-widget:role-critical-0',
        ),
      );
      final submitButton = tester.widget<IconButton>(submit);
      expect(submitButton.onPressed, isNotNull);
      await tester.runAsync(() async {
        container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-send-input-widget')
                  .notifier,
            )
            .restore(AiSeminarRuntimeState.initial().copyWith(
              session: runtimeSession,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              startedAt: 900,
              backgroundJob: const AiSeminarBackgroundJobSnapshot(
                id: 'job-send-input-widget',
                sessionId: 'seminar-chat-send-input-widget',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
              backgroundJobs: const [
                AiSeminarBackgroundJobSnapshot(
                  id: 'job-send-input-widget',
                  sessionId: 'seminar-chat-send-input-widget',
                  status: AiSeminarBackgroundJobStatus.running,
                  startedAt: 900,
                  updatedAt: 901,
                ),
              ],
            ));
        submitButton.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final readerTurn = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'reader_turn' && part.roleId == 'critical',
      );
      expect(readerTurn?.label, 'send-input');
      expect(readerTurn?.status, 'completed');
      expect(readerTurn?.completedAt, isNotNull);
      expect(readerTurn?.text, '请先解释还缺哪条原文证据。');
      expect(find.text('请先解释还缺哪条原文证据。'), findsOneWidget);
      expect(find.text('已处理'), findsOneWidget);
      expect(find.textContaining('处理时间'), findsOneWidget);

      List<AgentRunEvent>? events;
      await tester.runAsync(() async {
        events = await graphStore.listEvents(
          'seminar-chat-send-input-widget:role-critical-0',
        );
      });
      final inputEvent = events?.singleWhere(
        (event) => event.type == AgentRunEventType.userInput,
      );
      expect(inputEvent?.delta, '请先解释还缺哪条原文证据。');
      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-send-input-widget'),
      );
      expect(runtimeState.status, AiSeminarRunStatus.completed);
      expect(
        runtimeState.turns.single.responseText,
        'critical control response',
      );
      expect(prompts.single, contains('请先解释还缺哪条原文证据。'));
    },
  );

  testWidgets(
    'Seminar chat card marks cancelled child input control inline',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-send-input-cancelled-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final graphStore = AgentRunGraphStore();
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final evidenceBundle = AiSeminarEvidenceBundle(
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
      final runtimeSession = AiSeminarSessionContract(
        id: 'seminar-chat-send-input-cancelled-widget',
        question: '这个概念怎么理解？',
        bookId: 7,
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.synthesizer,
            enabled: false,
          ),
        ],
      );
      final runtimeService = AiSeminarRuntimeService(
        fetchEvidence: (_) => fail('active runtime should reuse evidence'),
        streamRole: (invocation, token) async* {
          yield AiSeminarRoleStreamChunk(
            partialText: '${invocation.role.asString} partial before cancel',
          );
          token.cancel();
        },
        agentRunGraphStore: graphStore,
        now: () => 1500,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
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
      await tester.runAsync(() async {
        await container.read(aiChatProvider.future);
        container.read(aiChatProvider.notifier).restore(
          [ChatMessage.humanText('已有会话')],
          sessionId: 'session-seminar-send-input-cancelled-widget',
        );
        await container.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: '这个概念怎么理解？',
              bookId: 7,
              seminarSessionId: 'seminar-chat-send-input-cancelled-widget',
            );
        await container
            .read(aiChatProvider.notifier)
            .updateSeminarRunCardSnapshot(
              seminarSessionId: 'seminar-chat-send-input-cancelled-widget',
              status: 'running',
              snapshot: const AiSeminarRunCardSnapshot(
                messageParts: [
                  AiSeminarRunCardMessagePart(
                    type: 'agent_status',
                    id: 'seminar-chat-send-input-cancelled-widget:role-critical-0:status:waiting_input',
                    agentRunId:
                        'seminar-chat-send-input-cancelled-widget:role-critical-0',
                    parentRunId: 'seminar-chat-send-input-cancelled-widget',
                    roleId: 'critical',
                    label: 'role-waiting-input',
                    text: 'Critical is waiting for input.',
                    actionIds: ['send-input', 'close-agent'],
                  ),
                ],
              ),
            );
      });

      final startedAt = DateTime.utc(2026, 6, 5, 2, 30);
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-send-input-cancelled-widget',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-send-input-cancelled-widget:role-critical-0',
          parentRunId: 'seminar-chat-send-input-cancelled-widget',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.waitingInput,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final sendAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-send-input-'
          'seminar-chat-send-input-cancelled-widget:role-critical-0',
        ),
      );
      expect(sendAction, findsOneWidget);

      final sendChip = tester.widget<ActionChip>(sendAction);
      sendChip.onPressed?.call();
      await tester.pump();

      final input = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-input-'
          'seminar-chat-send-input-cancelled-widget:role-critical-0',
        ),
      );
      expect(input, findsOneWidget);
      await tester.enterText(input, '这次先取消续跑。');
      await tester.pump();

      final submit = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-input-submit-'
          'seminar-chat-send-input-cancelled-widget:role-critical-0',
        ),
      );
      final submitButton = tester.widget<IconButton>(submit);
      expect(submitButton.onPressed, isNotNull);
      await tester.runAsync(() async {
        container
            .read(
              aiSeminarRuntimeScopedProvider(
                'seminar-chat-send-input-cancelled-widget',
              ).notifier,
            )
            .restore(AiSeminarRuntimeState.initial().copyWith(
              session: runtimeSession,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              startedAt: 900,
              backgroundJob: const AiSeminarBackgroundJobSnapshot(
                id: 'job-send-input-cancelled-widget',
                sessionId: 'seminar-chat-send-input-cancelled-widget',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
              backgroundJobs: const [
                AiSeminarBackgroundJobSnapshot(
                  id: 'job-send-input-cancelled-widget',
                  sessionId: 'seminar-chat-send-input-cancelled-widget',
                  status: AiSeminarBackgroundJobStatus.running,
                  startedAt: 900,
                  updatedAt: 901,
                ),
              ],
            ));
        submitButton.onPressed?.call();
      });
      AiSeminarRunCardMessagePart? readerTurn;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(2);
        final readerTurns = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'reader_turn' && part.roleId == 'critical',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        final runtimeState = container.read(
          aiSeminarRuntimeScopedProvider(
            'seminar-chat-send-input-cancelled-widget',
          ),
        );
        if (readerTurns.isNotEmpty &&
            runtimeState.status == AiSeminarRunStatus.cancelled) {
          readerTurn = readerTurns.single;
          break;
        }
      }
      readerTurn ??= container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2)
          ?.snapshot
          ?.messageParts
          .where(
            (part) => part.type == 'reader_turn' && part.roleId == 'critical',
          )
          .firstOrNull;
      expect(
        readerTurn,
        isNotNull,
        reason:
            'The current card should show the cancelled send-input reader turn.',
      );
      expect(readerTurn?.label, 'send-input');
      expect(readerTurn?.status, 'cancelled');
      expect(readerTurn?.completedAt, isNotNull);
      expect(readerTurn?.text, '这次先取消续跑。');
      await tester.pump();
      expect(find.text('这次先取消续跑。'), findsOneWidget);
      expect(find.text('已取消'), findsWidgets);

      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider(
          'seminar-chat-send-input-cancelled-widget',
        ),
      );
      expect(runtimeState.status, AiSeminarRunStatus.cancelled);
    },
  );

  testWidgets(
    'Seminar chat card resumes an interrupted child agent natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-resume-agent-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final graphStore = AgentRunGraphStore();
      final prompts = <String>[];
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final evidenceBundle = AiSeminarEvidenceBundle(
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
      final runtimeSession = AiSeminarSessionContract(
        id: 'seminar-chat-resume-agent-widget',
        question: '这个概念怎么理解？',
        bookId: 7,
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.synthesizer,
            enabled: false,
          ),
        ],
      );
      final runtimeService = AiSeminarRuntimeService(
        fetchEvidence: (_) => fail('active runtime should reuse evidence'),
        streamRole: (invocation, _) async* {
          prompts.add(invocation.prompt);
          yield AiSeminarRoleStreamChunk(
            completedTurn: AiSeminarRoleTurn(
              id: 'turn-resume-critical',
              role: invocation.role,
              prompt: invocation.prompt,
              responseText: 'critical resumed response',
              evidenceRefIds: const ['e1'],
            ),
          );
        },
        agentRunGraphStore: graphStore,
        now: () => 1500,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
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
      await tester.runAsync(() async {
        await container.read(aiChatProvider.future);
        container.read(aiChatProvider.notifier).restore(
          [ChatMessage.humanText('已有会话')],
          sessionId: 'session-seminar-resume-agent-widget',
        );
        await container.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: '这个概念怎么理解？',
              bookId: 7,
              seminarSessionId: 'seminar-chat-resume-agent-widget',
            );
        await container
            .read(aiChatProvider.notifier)
            .updateSeminarRunCardSnapshot(
              seminarSessionId: 'seminar-chat-resume-agent-widget',
              status: 'running',
              snapshot: const AiSeminarRunCardSnapshot(
                messageParts: [
                  AiSeminarRunCardMessagePart(
                    type: 'director_state',
                    id: 'seminar-chat-resume-agent-widget:role-critical-0:status:interrupted',
                    roleId: 'critical',
                    label: 'role-interrupted',
                    text: 'Critical was interrupted.',
                    actionIds: ['resume-agent', 'close-agent'],
                  ),
                ],
              ),
            );
      });

      final startedAt = DateTime.utc(2026, 6, 4, 20, 30);
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-resume-agent-widget',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-resume-agent-widget:role-critical-0',
          parentRunId: 'seminar-chat-resume-agent-widget',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.interrupted,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final resumeAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-resume-agent-'
          'seminar-chat-resume-agent-widget:role-critical-0',
        ),
      );
      expect(resumeAction, findsOneWidget);

      final resumeChip = tester.widget<ActionChip>(resumeAction);
      await tester.runAsync(() async {
        container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-resume-agent-widget')
                  .notifier,
            )
            .restore(AiSeminarRuntimeState.initial().copyWith(
              session: runtimeSession,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              startedAt: 900,
              backgroundJob: const AiSeminarBackgroundJobSnapshot(
                id: 'job-resume-agent-widget',
                sessionId: 'seminar-chat-resume-agent-widget',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
              backgroundJobs: const [
                AiSeminarBackgroundJobSnapshot(
                  id: 'job-resume-agent-widget',
                  sessionId: 'seminar-chat-resume-agent-widget',
                  status: AiSeminarBackgroundJobStatus.running,
                  startedAt: 900,
                  updatedAt: 901,
                ),
              ],
            ));
        resumeChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      List<AgentRunEvent>? events;
      await tester.runAsync(() async {
        events = await graphStore.listEvents(
          'seminar-chat-resume-agent-widget:role-critical-0',
        );
      });
      final resumeEvent = events?.singleWhere(
        (event) => event.type == AgentRunEventType.resumeRequest,
      );
      expect(resumeEvent?.delta, isNull);
      final readerTurns = card?.snapshot?.messageParts
              .where(
                (part) =>
                    part.type == 'reader_turn' && part.roleId == 'critical',
              )
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      final statusParts = card?.snapshot?.messageParts
              .where(
                (part) =>
                    part.type == 'director_state' && part.roleId == 'critical',
              )
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      expect(readerTurns, hasLength(1));
      expect(readerTurns.single.label, 'resume-agent');
      expect(readerTurns.single.text, isNull);
      expect(
        statusParts.map((part) => part.label),
        isNot(contains('role-interrupted')),
      );
      expect(find.text('Resume requested.'), findsNothing);
      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-resume-agent-widget'),
      );
      expect(runtimeState.status, AiSeminarRunStatus.completed);
      expect(
        runtimeState.turns.single.responseText,
        'critical resumed response',
      );
      expect(prompts.single, contains('Resume requested.'));
    },
  );

  testWidgets(
    'Seminar chat card retries a failed child agent natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-retry-agent-widget-');
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final graphStore = AgentRunGraphStore();
      final prompts = <String>[];
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final evidenceBundle = AiSeminarEvidenceBundle(
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
      final runtimeSession = AiSeminarSessionContract(
        id: 'seminar-chat-retry-agent-widget',
        question: '这个概念怎么理解？',
        bookId: 7,
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.synthesizer,
            enabled: false,
          ),
        ],
      );
      final runtimeService = AiSeminarRuntimeService(
        fetchEvidence: (_) => fail('active runtime should reuse evidence'),
        streamRole: (invocation, _) async* {
          prompts.add(invocation.prompt);
          yield AiSeminarRoleStreamChunk(
            completedTurn: AiSeminarRoleTurn(
              id: 'turn-retry-critical',
              role: invocation.role,
              prompt: invocation.prompt,
              responseText: 'critical retried response',
              evidenceRefIds: const ['e1'],
            ),
          );
        },
        agentRunGraphStore: graphStore,
        now: () => 1500,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
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
      await tester.runAsync(() async {
        await container.read(aiChatProvider.future);
        container.read(aiChatProvider.notifier).restore(
          [ChatMessage.humanText('已有会话')],
          sessionId: 'session-seminar-retry-agent-widget',
        );
        await container.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: '这个概念怎么理解？',
              bookId: 7,
              seminarSessionId: 'seminar-chat-retry-agent-widget',
            );
        await container
            .read(aiChatProvider.notifier)
            .updateSeminarRunCardSnapshot(
              seminarSessionId: 'seminar-chat-retry-agent-widget',
              status: 'running',
              snapshot: const AiSeminarRunCardSnapshot(
                messageParts: [
                  AiSeminarRunCardMessagePart(
                    type: 'agent_status',
                    id: 'seminar-chat-retry-agent-widget:role-critical-0:status:errored',
                    agentRunId:
                        'seminar-chat-retry-agent-widget:role-critical-0',
                    parentRunId: 'seminar-chat-retry-agent-widget',
                    roleId: 'critical',
                    label: 'role-error',
                    text: 'Critical failed.',
                    actionIds: ['retry-agent-control'],
                  ),
                ],
              ),
            );
      });

      final startedAt = DateTime.utc(2026, 6, 4, 21, 30);
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-retry-agent-widget',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-retry-agent-widget:role-critical-0',
          parentRunId: 'seminar-chat-retry-agent-widget',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.errored,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
          finishedAt: startedAt.add(const Duration(seconds: 5)),
          error: 'provider timeout',
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final retryAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-agent-action-retry-agent-control-'
          'seminar-chat-retry-agent-widget:role-critical-0',
        ),
      );
      expect(retryAction, findsOneWidget);

      final retryChip = tester.widget<ActionChip>(retryAction);
      await tester.runAsync(() async {
        container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-retry-agent-widget')
                  .notifier,
            )
            .restore(AiSeminarRuntimeState.initial().copyWith(
              session: runtimeSession,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              startedAt: 900,
              backgroundJob: const AiSeminarBackgroundJobSnapshot(
                id: 'job-retry-agent-widget',
                sessionId: 'seminar-chat-retry-agent-widget',
                status: AiSeminarBackgroundJobStatus.running,
                startedAt: 900,
                updatedAt: 901,
              ),
              backgroundJobs: const [
                AiSeminarBackgroundJobSnapshot(
                  id: 'job-retry-agent-widget',
                  sessionId: 'seminar-chat-retry-agent-widget',
                  status: AiSeminarBackgroundJobStatus.running,
                  startedAt: 900,
                  updatedAt: 901,
                ),
              ],
            ));
        retryChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      List<AgentRunEvent>? events;
      await tester.runAsync(() async {
        events = await graphStore.listEvents(
          'seminar-chat-retry-agent-widget:role-critical-0',
        );
      });
      final retryEvent = events?.singleWhere(
        (event) => event.type == AgentRunEventType.retryRequest,
      );
      expect(retryEvent?.delta, isNull);
      expect(retryEvent?.acknowledgedAt, isNotNull);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(2);
      final readerTurn = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'reader_turn' && part.roleId == 'critical',
      );
      final roleTurn = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'role_turn' && part.roleId == 'critical',
      );
      expect(readerTurn?.label, 'retry-agent-control');
      expect(readerTurn?.status, 'completed');
      expect(readerTurn?.completedAt, isNotNull);
      expect(readerTurn?.text, isNull);
      expect(find.text('Retry requested.'), findsNothing);
      expect(
        readerTurn?.agentRunId,
        'seminar-chat-retry-agent-widget:role-critical-0',
      );
      expect(readerTurn?.parentRunId, 'seminar-chat-retry-agent-widget');
      expect(roleTurn?.text, 'critical retried response');
      expect(find.text('已处理'), findsOneWidget);
      expect(find.textContaining('处理时间'), findsOneWidget);

      final runtimeState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-retry-agent-widget'),
      );
      expect(runtimeState.status, AiSeminarRunStatus.completed);
      expect(
        runtimeState.turns.single.responseText,
        'critical retried response',
      );
      expect(prompts.single, contains('Retry requested.'));
    },
  );

  testWidgets(
    'persisted Seminar chat card renders reader composer message parts',
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
              useReaderComposerMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('可用动作'), findsOneWidget);
      expect(find.text('让角色回应'), findsAtLeastNWidgets(1));
      expect(find.text('重新找证据'), findsOneWidget);
      expect(find.text('整理总结'), findsOneWidget);
      expect(find.text('可回应角色'), findsOneWidget);
      expect(find.text('批判者'), findsAtLeastNWidgets(1));
      expect(find.text('支持者'), findsAtLeastNWidgets(1));
      expect(find.text('默认动作'), findsOneWidget);
      expect(find.text('默认角色'), findsOneWidget);
      expect(find.text('当前动作'), findsOneWidget);
      expect(find.text('当前角色'), findsOneWidget);
      expect(find.text('草稿回复'), findsOneWidget);
      expect(
        find.text('I want the supporter to test this question.'),
        findsOneWidget,
      );
      expect(
        find.text('Which interpretation should the reader test next?'),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('seminar-chat-card-reply-seminar-chat-history'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'persisted legacy Seminar card preserves all reader composer message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2200);
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
              useLegacyMultipleReaderComposerMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('读者参与'), findsOneWidget);
      expect(find.text('Reader composer 1.'), findsOneWidget);
      expect(find.text('Reader composer 2.'), findsOneWidget);
      expect(
        find.text('Reader composer 3 should stay visible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card shows evidence tool calls',
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
            _seminarCardHistoryEntry(includeToolCalls: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
      expect(find.text('1 个结果'), findsOneWidget);
      expect(find.text('可见角色'), findsOneWidget);
      expect(find.text('批判者、支持者'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:role-critical-0'), findsOneWidget);
      expect(find.text('Tool call evidence.'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted Seminar chat card renders tool call message parts',
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
              useToolCallMessagePartsOnly: true,
              keepEvidenceForToolCallMessageParts: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
      expect(find.text('1 个结果'), findsOneWidget);
      expect(find.text('可见角色'), findsOneWidget);
      expect(find.text('批判者、支持者'), findsOneWidget);
      expect(find.text('工具输出'), findsOneWidget);
      expect(find.text('Returned 1 traceable evidence chunk.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:role-critical-0'), findsOneWidget);
      expect(find.text('Tool call evidence.'), findsAtLeastNWidgets(1));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('工具输出'), findsOneWidget);
      expect(find.text('Returned 1 traceable evidence chunk.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar tool call details render available controls',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'running',
              toolCallMessagePartActionIds: const [
                'wait-tool-call',
                'cancel-tool-call',
              ],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('可用控制'), findsOneWidget);
      expect(find.text('等待工具调用'), findsOneWidget);
      expect(find.text('取消工具调用'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-tool-action-wait-tool-call-tool-call-1',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'persisted Seminar terminal tool call controls are not executable',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'completed',
              toolCallMessagePartCompletedAt: 1717516802000,
              toolCallMessagePartActionIds: const [
                'wait-tool-call',
                'cancel-tool-call',
              ],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('调用完成'), findsOneWidget);
      expect(find.text('历史控制'), findsOneWidget);
      expect(find.text('可用控制'), findsNothing);
      expect(find.text('等待工具调用'), findsOneWidget);
      expect(find.text('取消工具调用'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-tool-action-wait-tool-call-tool-call-1',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-tool-action-cancel-tool-call-tool-call-1',
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'persisted Seminar running tool call cancels containing role natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-cancel-tool-call-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      final startedAt = DateTime.utc(2026, 6, 6, 15);
      final graphStore = AgentRunGraphStore();
      await tester.runAsync(() async {
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'director',
          roleId: 'director',
          nickname: 'Director',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt,
        ));
        await graphStore.upsertRun(AgentRunRecord(
          runId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          source: 'seminar',
          profile: 'critical',
          roleId: 'critical',
          nickname: 'Critical',
          status: SubAgentRunStatus.running,
          task: '这个概念怎么理解？',
          startedAt: startedAt.add(const Duration(seconds: 1)),
        ));
        await graphStore.upsertEvent(AgentRunEvent(
          eventId: 'tool-call-1',
          runId: 'seminar-chat-history:role-critical-0',
          parentRunId: 'seminar-chat-history',
          type: AgentRunEventType.toolCall,
          createdAt: startedAt.add(const Duration(seconds: 2)),
          status: SubAgentRunStatus.running,
          roleId: 'critical',
          nickname: 'Critical',
          toolId: 'semantic_search_current_book',
          query: '这个概念怎么理解？',
          roleIds: ['critical'],
        ));
      });

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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'running',
              toolCallMessagePartStartedAt: startedAt
                  .add(const Duration(seconds: 2))
                  .millisecondsSinceEpoch,
              toolCallMessagePartActionIds: const ['cancel-tool-call'],
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      final cancelAction = find.byKey(
        const ValueKey(
          'seminar-chat-card-tool-action-cancel-tool-call-tool-call-1',
        ),
      );
      expect(cancelAction, findsOneWidget);

      final cancelChip = tester.widget<ActionChip>(cancelAction);
      await tester.runAsync(() async {
        cancelChip.onPressed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final childRun = await tester.runAsync<AgentRunRecord?>(
        () => graphStore.getRun('seminar-chat-history:role-critical-0'),
      );
      expect(childRun?.status, SubAgentRunStatus.shutdown);

      final events = await tester.runAsync<List<AgentRunEvent>>(
        () => graphStore.listEvents('seminar-chat-history:role-critical-0'),
      );
      expect(events, isNotNull);
      final toolEvent = events!.singleWhere(
        (event) => event.eventId == 'tool-call-1',
      );
      expect(toolEvent.status, SubAgentRunStatus.shutdown);

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final toolPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'tool_call' && part.id == 'tool-call-1',
      );
      final cancelTurn = card?.snapshot?.messageParts.singleWhere(
        (part) =>
            part.type == 'reader_turn' && part.label == 'cancel-tool-call',
      );
      expect(toolPart?.status, 'shutdown');
      expect(toolPart?.actionIds, isEmpty);
      expect(cancelTurn?.status, 'completed');
      expect(cancelTurn?.toolId, 'semantic_search_current_book');
      expect(cancelTurn?.query, '这个概念怎么理解？');
      expect(find.text('已停止'), findsWidgets);
      expect(find.text('取消工具调用'), findsNothing);

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-overview-seminar-chat-history',
      )));
      await tester.pump();
      expect(find.text('取消工具调用 · 批判者'), findsOneWidget);
      expect(find.text('工具：书内语义检索'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(find.text('已处理'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar tool calls tab shows all snapshot calls',
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
              includeToolCalls: true,
              useSnapshotMultipleToolCalls: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 1.'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 2.'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 3.'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 4.'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 5.'), findsOneWidget);
      expect(find.text('Returned snapshot tool call 6.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders tool call execution time',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'completed',
              toolCallMessagePartStartedAt: 1717516800000,
              toolCallMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用完成'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsOneWidget);
      expect(find.textContaining('耗时'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar tool call shows all returned evidence sources',
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
              useToolCallMessagePartsOnly: true,
              useToolCallMultipleEvidenceRefs: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('3 个结果'), findsOneWidget);
      expect(find.text('返回证据'), findsOneWidget);
      expect(find.text('Tool call evidence.'), findsOneWidget);
      expect(find.text('Second tool call evidence.'), findsOneWidget);
      expect(find.text('Third tool call evidence.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders running tool call start time',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'running',
              toolCallMessagePartStartedAt: 1717516801000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用中'), findsOneWidget);
      expect(find.textContaining('开始时间'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders pending tool call as running',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'pendingInit',
              toolCallMessagePartStartedAt: 1717516801000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用中'), findsOneWidget);
      expect(find.textContaining('开始时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card hides stale execution time for running tool calls',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'running',
              toolCallMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用中'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted reading Seminar role tool calls hide library fallback tools',
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
              useToolCallMessagePartsOnly: true,
              keepEvidenceForToolCallMessageParts: true,
              includeLibraryFallbackToolCallMessagePart: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('Returned library-wide evidence.'), findsNothing);
      expect(find.text('Library fallback tool evidence.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('Returned library-wide evidence.'), findsNothing);
    },
  );

  testWidgets(
    'persisted reading Seminar evidence tool calls hide disabled library scope',
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
              useToolCallMessagePartsOnly: true,
              keepEvidenceForToolCallMessageParts: true,
              useParentEvidenceToolCallMessageParts: true,
              includeLibraryFallbackToolCallMessagePart: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('Returned library-wide evidence.'), findsNothing);
      expect(find.text('Library fallback tool evidence.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('工具调用详情'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('Returned library-wide evidence.'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders artifact action audit details',
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
              useArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('KnowledgeCard saved.'), findsOneWidget);
      expect(find.text('已保存知识卡'), findsOneWidget);
      expect(find.text('已处理'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsOneWidget);
      expect(find.text('执行结果'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted Seminar artifact actions only card exposes artifact tab',
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
              useArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('KnowledgeCard saved.'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-artifacts-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('沉淀动作详情'), findsOneWidget);
      expect(find.text('已处理'), findsOneWidget);
      expect(find.text('执行结果'), findsOneWidget);
      expect(find.text('KnowledgeCard saved.'), findsOneWidget);
      expect(find.text('已保存知识卡'), findsOneWidget);
      expect(find.text('Artifact action evidence.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar source-missing artifact actions render localized triage copy',
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
              useSourceMissingArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('已中断'), findsOneWidget);
      expect(find.text('中断原因'), findsOneWidget);
      expect(find.text('来源缺失'), findsOneWidget);
      expect(find.text('异常送审'), findsOneWidget);
      expect(find.text('已保存知识卡'), findsNothing);
      expect(
        find.text('缺少可追溯来源，不能直接保存为知识资产；请先送入异常处理。'),
        findsOneWidget,
      );
      expect(
        find.textContaining('missing traceable source evidence'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card renders pendingInit artifact actions as processing',
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
              usePendingInitArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(
          find.text('KnowledgeCard save is being accepted.'), findsOneWidget);
      expect(find.text('处理中'), findsOneWidget);
      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('知识卡'), findsNothing);
      expect(find.text('处理说明'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders errored artifact action time label',
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
              useErroredArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('KnowledgeCard save failed.'), findsOneWidget);
      expect(find.text('处理失败'), findsOneWidget);
      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('知识卡'), findsNothing);
      expect(find.text('失败原因'), findsOneWidget);
      expect(find.textContaining('失败时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders missing artifact action time label',
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
              useMissingArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('KnowledgeCard save action was not found.'),
          findsOneWidget);
      expect(find.text('操作未找到'), findsOneWidget);
      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('知识卡'), findsNothing);
      expect(find.text('未找到原因'), findsOneWidget);
      expect(find.textContaining('未找到时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders cancelled artifact action time label',
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
              useCancelledArtifactActionsMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('KnowledgeCard save was cancelled.'), findsOneWidget);
      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('保存知识卡'), findsOneWidget);
      expect(find.text('知识卡'), findsNothing);
      expect(find.text('取消原因'), findsOneWidget);
      expect(find.textContaining('取消时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders errored tool call status',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'errored',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用失败'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders completed tool call status',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'completed',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用完成'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders missing tool call status',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'notFound',
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('调用未找到'), findsOneWidget);
      expect(find.text('调用中'), findsNothing);
      expect(find.text('未找到原因'), findsOneWidget);
      expect(find.text('工具输出'), findsNothing);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders interrupted and stopped tool call detail labels',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'interrupted',
              toolCallMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已中断'), findsOneWidget);
      expect(find.text('中断原因'), findsOneWidget);
      expect(find.textContaining('中断时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
      expect(find.text('工具输出'), findsNothing);

      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'shutdown',
              toolCallMessagePartCompletedAt: 1717516803000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已停止'), findsOneWidget);
      expect(find.text('停止原因'), findsOneWidget);
      expect(find.textContaining('停止时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
      expect(find.text('工具输出'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders cancelled tool call status',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'cancelled',
              toolCallMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('取消原因'), findsOneWidget);
      expect(find.textContaining('取消时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
      expect(find.text('工具输出'), findsNothing);
      expect(find.text('调用中'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card treats canceled tool calls as cancelled',
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
              useToolCallMessagePartsOnly: true,
              toolCallMessagePartStatus: 'canceled',
              toolCallMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已取消'), findsOneWidget);
      expect(find.text('取消原因'), findsOneWidget);
      expect(find.textContaining('取消时间'), findsOneWidget);
      expect(find.textContaining('执行时间'), findsNothing);
      expect(find.text('工具输出'), findsNothing);
      expect(find.text('调用中'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders message parts as a native timeline',
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
            _seminarCardHistoryEntry(useNativeTimelineMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('Native stream evidence bundle.'), findsOneWidget);
      expect(find.text('Native stream role turn.'), findsOneWidget);
      expect(find.text('Native stream director cue.'), findsOneWidget);
      expect(find.text('Native stream synthesis.'), findsOneWidget);

      final toolTop = tester.getTopLeft(find.text('书内语义检索')).dy;
      final evidenceTop =
          tester.getTopLeft(find.text('Native stream evidence bundle.')).dy;
      final roleTop =
          tester.getTopLeft(find.text('Native stream role turn.')).dy;
      final directorTop =
          tester.getTopLeft(find.text('Native stream director cue.')).dy;
      final synthesisTop =
          tester.getTopLeft(find.text('Native stream synthesis.')).dy;

      expect(toolTop, lessThan(evidenceTop));
      expect(evidenceTop, lessThan(roleTop));
      expect(roleTop, lessThan(directorTop));
      expect(directorTop, lessThan(synthesisTop));
    },
  );

  testWidgets(
    'persisted Seminar chat card renders thinking message parts natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
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
              useThinkingMessagePartsOnly: true,
              thinkingMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('思考'), findsAtLeastNWidgets(1));
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('Critical is preparing an evidence-grounded response.'),
          findsOneWidget);
      expect(find.textContaining('思考时间'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar thinking only card exposes thinking tab',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
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
              useThinkingMessagePartsOnly: true,
              thinkingMessagePartCompletedAt: 1717516802000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('思考'), findsAtLeastNWidgets(1));

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-thinking-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('思考详情'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('Critical is preparing an evidence-grounded response.'),
          findsOneWidget);
      expect(find.textContaining('思考时间'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar verifier thinking uses product role label',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
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
              useThinkingMessagePartsOnly: true,
              thinkingMessagePartRoleId: 'verifier',
              thinkingMessagePartLabel: null,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('思考'), findsAtLeastNWidgets(1));
      expect(find.text('核验者'), findsOneWidget);
      expect(find.text('验证者'), findsNothing);
      expect(find.text('Verifier is checking cited evidence.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar native stream shows agent trace for role and reader parts',
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
              useNativeTimelineAgentTraceMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('Native traced role turn.'), findsOneWidget);
      expect(find.text('Native traced role partial.'), findsOneWidget);
      expect(find.text('Native traced director state.'), findsOneWidget);
      expect(find.text('Native traced reader turn.'), findsOneWidget);
      expect(find.text('运行追踪'), findsAtLeastNWidgets(4));
      expect(find.text('父运行'), findsAtLeastNWidgets(4));
      expect(find.text('seminar-chat-history:role-critical-0'), findsOneWidget);
      expect(
        find.text('seminar-chat-history:role-supportive-1'),
        findsOneWidget,
      );
      expect(find.text('seminar-chat-history:director'), findsOneWidget);
      expect(
        find.text('seminar-chat-history:role-verifier-2'),
        findsOneWidget,
      );
      expect(find.text('seminar-chat-history'), findsAtLeastNWidgets(4));
    },
  );

  testWidgets(
    'persisted Seminar chat card renders setup message parts natively',
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
            _seminarCardHistoryEntry(useRunSetupMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('本次设置'), findsOneWidget);
      expect(find.text('问题：这个概念怎么理解？'), findsOneWidget);
      expect(find.text('角色：批判者、支持者 · 证据：当前书籍 · 轮次：2'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card expands the full native stream in card',
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
          .loadHistoryEntry(_seminarCardHistoryEntry(
            extraLegacyDisagreement: 'Unique hidden disagreement.',
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.textContaining('研讨片段可在分类视图中查看'), findsOneWidget);
      expect(find.text('Unique hidden disagreement.'), findsNothing);

      expect(find.text('展开全部研讨流'), findsOneWidget);
      await tester.tap(find.text('展开全部研讨流'));
      await tester.pumpAndSettle();

      expect(find.text('Unique hidden disagreement.'), findsOneWidget);
      expect(find.text('收起研讨流'), findsOneWidget);

      await tester.tap(find.text('收起研讨流'));
      await tester.pumpAndSettle();

      expect(find.textContaining('研讨片段可在分类视图中查看'), findsOneWidget);
      expect(find.text('Unique hidden disagreement.'), findsNothing);
    },
  );

  testWidgets(
    'persisted legacy Seminar snapshot renders native stream with source action',
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
            _seminarCardHistoryEntry(
              includeSnapshotSourceRef: true,
              includeToolCalls: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsWidgets);
      expect(
          find.text('This claim needs a boundary condition.'), findsOneWidget);
      expect(find.text('The group agrees on the mechanism but not the scope.'),
          findsOneWidget);
      expect(find.text('打开来源'), findsWidgets);

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
    'completed Seminar chat card keeps thinking and asset actions after native stream overview',
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('开始研讨'));
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final completedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(completedCard?.status, 'completed');
      expect(
        completedCard?.snapshot?.messageParts.map((part) => part.type).toSet(),
        containsAll({
          'tool_call',
          'evidence',
          'thinking',
          'role_turn',
          'synthesis',
          'artifact_actions',
        }),
      );
      final artifactActionsPart =
          completedCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        artifactActionsPart?.actionIds,
        containsAll({
          'save-knowledge-card',
          'edit-knowledge-card',
          'add-spaced-review',
          'add-concept-graph',
          'send-to-review',
          'ignore-artifact-actions',
        }),
      );
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('思考'), findsAtLeastNWidgets(1));
      expect(
        find.text('主持人正在等待你的选择，以决定继续追问、补证据还是整理总结。'),
        findsOneWidget,
      );
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('critical response'), findsOneWidget);
      expect(find.text('synthesizer response'), findsAtLeastNWidgets(1));

      await tester.ensureVisible(
        find.text('保存知识卡').last,
      );
      await _ensureVisibleAndTap(
        tester,
        find.text('保存知识卡').last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final seminarCards =
          await cardStore.list(origin: KnowledgeCardOrigin.seminar);
      expect(seminarCards, hasLength(1));
      expect(seminarCards.single.explanation, 'synthesizer response');
      expect(find.textContaining('已保存为知识卡'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted native Seminar stream keeps artifact actions in collapsed view',
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
              useLongNativeTimelineWithArtifactActions: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('Long native role turn 1.'), findsOneWidget);
      expect(find.text('沉淀动作'), findsOneWidget);
      expect(find.text('保存知识卡'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted native Seminar stream keeps review triage in collapsed view',
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
              useLongNativeTimelineWithReviewTriage: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('Long native role turn 1.'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('中风险'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
      expect(find.text('送入异常中心'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders synthesis message parts',
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
            _seminarCardHistoryEntry(useSynthesisMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('Synthesis part summary.'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted Seminar synthesis marks linked evidence without source',
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
            _seminarCardHistoryEntry(useSynthesisMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
      expect(find.text('来源缺失'), findsOneWidget);
      expect(find.text('打开来源'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar synthesis linked evidence opens source inline',
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
            _seminarCardHistoryEntry(
              useSynthesisMessagePartsOnly: true,
              useSynthesisMessagePartSourceRef: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
      expect(find.text('打开来源'), findsOneWidget);

      await tester.tap(find.text('打开来源'));
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
    'persisted Seminar synthesis shows all linked evidence sources inline',
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
            _seminarCardHistoryEntry(
              useSynthesisMessagePartsOnly: true,
              useSynthesisMessagePartSourceRef: true,
              useSynthesisMultipleEvidenceRefs: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('Second synthesis evidence.'), findsOneWidget);
      expect(find.text('Third synthesis evidence.'), findsOneWidget);
      expect(find.text('打开来源'), findsNWidgets(3));

      await tester.tap(find.text('打开来源').at(2));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(opened.single.queryParameters['cfi'], 'epubcfi(/6/12)');
    },
  );

  testWidgets(
    'persisted Seminar chat card renders disagreement message parts',
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
            _seminarCardHistoryEntry(useDisagreementMessagePartsOnly: true),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧视图'), findsOneWidget);
      expect(find.text('Disagreement part text.'), findsOneWidget);
      expect(find.text('关联角色'), findsOneWidget);
      expect(find.text('批判者、支持者'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:director:disagreement'),
          findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar disagreements tab shows all disagreement message parts',
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
              useMultipleDisagreementMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('Disagreement part 1.'), findsOneWidget);
      expect(find.text('Disagreement part 2.'), findsOneWidget);
      expect(find.text('Disagreement part 3.'), findsOneWidget);
      expect(find.text('Disagreement part 4.'), findsOneWidget);
      expect(find.text('Disagreement part 5.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders contradiction scan message parts',
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
              useContradictionScanMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧扫描'), findsOneWidget);
      expect(find.text('Scope remains disputed.'), findsOneWidget);
      expect(find.text('关联角色'), findsOneWidget);
      expect(find.text('批判者、支持者'), findsOneWidget);
      expect(find.text('关联证据'), findsOneWidget);
      expect(find.text('Scan evidence snippet.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:director:scan'), findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar disagreements tab shows all contradiction scan message parts',
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
              useMultipleContradictionScanMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('Contradiction scan 1.'), findsOneWidget);
      expect(find.text('Contradiction scan 2.'), findsOneWidget);
      expect(find.text('Contradiction scan 3.'), findsOneWidget);
      expect(find.text('Contradiction scan 4.'), findsOneWidget);
      expect(find.text('Contradiction scan 5.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card renders contradiction evidence gap scans',
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
              useContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧扫描'), findsOneWidget);
      expect(find.text('证据缺口'), findsOneWidget);
      expect(
        find.text('Scope remains disputed without traceable evidence.'),
        findsOneWidget,
      );
      expect(find.text('缺少可追踪证据'), findsOneWidget);
      expect(find.text('证据缺口汇总'), findsNothing);
      expect(find.text('关联证据'), findsNothing);
    },
  );

  testWidgets(
    'persisted Seminar chat card prioritizes contradiction evidence gaps',
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
              useMixedContradictionScanMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧扫描'), findsNWidgets(2));
      expect(find.text('证据缺口'), findsOneWidget);
      final gapTop = tester.getTopLeft(
        find.text('Missing evidence scope dispute.'),
      );
      final backedTop = tester.getTopLeft(
        find.text('Evidence-backed scope dispute.'),
      );

      expect(gapTop.dy, lessThan(backedTop.dy));
    },
  );

  testWidgets(
    'persisted Seminar chat card aggregates contradiction evidence gaps',
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
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('证据缺口汇总'), findsOneWidget);
      expect(find.text('3 条证据缺口'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap A.'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap B.'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap C.'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'persisted Seminar evidence gap summary shows all gaps',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
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
              useFourContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('证据缺口汇总'), findsOneWidget);
      expect(find.text('4 条证据缺口'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap A.'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap B.'), findsAtLeastNWidgets(1));
      expect(find.text('Missing evidence gap C.'), findsAtLeastNWidgets(1));
      expect(
        find.text('Missing evidence gap D should stay visible.'),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'persisted Seminar chat card summarizes contradiction scan coverage',
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
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧扫描概览'), findsOneWidget);
      expect(find.text('4 条扫描'), findsOneWidget);
      expect(find.text('3 条证据缺口'), findsAtLeastNWidgets(1));
      expect(find.text('1 条已有证据'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card suggests contradiction scan next actions',
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
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('下一步建议'), findsOneWidget);
      expect(find.text('先围绕证据缺口重找证据'), findsOneWidget);
      expect(find.text('再让角色反驳已有证据分歧'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar chat card lists prioritized contradiction scans',
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
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('优先处理'), findsOneWidget);
      final gapATop =
          tester.getTopLeft(find.text('补证据：Missing evidence gap A.'));
      final gapBTop =
          tester.getTopLeft(find.text('补证据：Missing evidence gap B.'));
      final gapCTop =
          tester.getTopLeft(find.text('补证据：Missing evidence gap C.'));
      final backedTop = tester.getTopLeft(
        find.text('反驳：Evidence-backed scope dispute.'),
      );

      expect(gapATop.dy, lessThan(gapBTop.dy));
      expect(gapBTop.dy, lessThan(gapCTop.dy));
      expect(gapCTop.dy, lessThan(backedTop.dy));
    },
  );

  testWidgets(
    'Seminar chat card refreshes evidence from priority contradiction queue',
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
                includeDisagreementEvidenceRef: false,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useMultipleContradictionGapMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();
      expect(find.text('补证据：Missing evidence gap A.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-overview-seminar-chat-history',
      )));
      await tester.pump();

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      expect(evidenceFetches, ['e1']);
      final initialState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(
        initialState.directorState?.nextIntent,
        AiSeminarDirectorNextIntent.refreshEvidence,
      );
      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('优先处理'), findsOneWidget);
      expect(find.text('补证据：Missing evidence gap A.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-priority-refresh-disagreement-seminar-chat-history',
      )));
      await tester.pump();
      for (var i = 0; i < 125; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        final state = container.read(
          aiSeminarRuntimeScopedProvider('seminar-chat-history'),
        );
        if (state.directorState?.nextIntent ==
            AiSeminarDirectorNextIntent.end) {
          break;
        }
      }

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(evidenceFetches, ['e1', 'e2']);
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.refreshEvidence,
      );
      expect(
        state.directorState!.lastUserIntervention!.text,
        '围绕分歧重新找证据：Missing evidence gap A.',
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    },
  );

  testWidgets(
    'Seminar chat card rebuts evidence-backed priority contradiction queue item',
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('优先处理'), findsOneWidget);
      expect(
        find.text('反驳：Scope remains disputed.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-priority-rebut-disagreement-seminar-chat-history',
      )));
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

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
        contains(
          'Reader intervention: 围绕分歧继续反驳：Scope remains disputed.',
        ),
      );
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rebuttalPart = card?.snapshot?.messageParts.firstWhere(
        (part) =>
            part.type == 'disagreement_rebuttal' &&
            part.label == 'Scope remains disputed.',
      );
      expect(rebuttalPart?.roleId, 'critical');
      expect(rebuttalPart?.text, 'critical follow-up response');
    },
  );

  testWidgets(
    'persisted Seminar chat card renders disagreement rebuttal message parts',
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
              useDisagreementRebuttalMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('分歧反驳回合'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(find.text('Scope remains disputed.'), findsOneWidget);
      expect(find.text('critical follow-up response'), findsOneWidget);
      expect(find.text('The source passage.'), findsOneWidget);
      expect(find.text('运行追踪'), findsOneWidget);
      expect(find.text('seminar-chat-history:role-critical-1'), findsOneWidget);
      expect(find.text('父运行'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar disagreements tab shows all disagreement rebuttal message parts',
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
              useMultipleDisagreementRebuttalMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey(
        'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
      )));
      await tester.pump();

      expect(find.text('Rebuttal part 1.'), findsOneWidget);
      expect(find.text('Rebuttal part 2.'), findsOneWidget);
      expect(find.text('Rebuttal part 3.'), findsOneWidget);
      expect(find.text('Rebuttal part 4.'), findsOneWidget);
      expect(find.text('Rebuttal part 5.'), findsOneWidget);
    },
  );

  testWidgets(
    'running Seminar chat card shows live evidence tool calls before role output',
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
      final evidenceFetched = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarPendingEvidenceToolCallService(
                evidenceFetched: evidenceFetched,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, evidenceFetched.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('查询：这个概念怎么理解？'), findsOneWidget);
      expect(find.text('调用完成'), findsOneWidget);
      expect(find.text('工具输出'), findsOneWidget);
      expect(find.text('返回 1 条可追踪证据。'), findsOneWidget);
      expect(find.text('Live evidence before role output.'), findsOneWidget);

      releaseRole.complete();
      await _finishLiveSeminarWidgetRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
        runFuture: runFuture,
      );
    },
  );

  testWidgets(
    'running Seminar chat card shows pending evidence tool calls before evidence returns',
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
      final evidenceStarted = Completer<void>();
      final releaseEvidence = Completer<void>();

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
              _seminarBlockedEvidenceToolCallService(
                evidenceStarted: evidenceStarted,
                releaseEvidence: releaseEvidence,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              scopes: const [
                AiSeminarEvidenceScope.currentBook,
                AiSeminarEvidenceScope.library,
                AiSeminarEvidenceScope.notes,
                AiSeminarEvidenceScope.memory,
                AiSeminarEvidenceScope.conceptGraph,
              ],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  evidenceScopes: const [
                    AiSeminarEvidenceScope.currentBook,
                    AiSeminarEvidenceScope.library,
                    AiSeminarEvidenceScope.notes,
                    AiSeminarEvidenceScope.memory,
                    AiSeminarEvidenceScope.conceptGraph,
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, evidenceStarted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('书内语义检索'), findsOneWidget);
      expect(find.text('书库语义检索'), findsOneWidget);
      expect(find.text('笔记搜索'), findsOneWidget);
      expect(find.text('记忆搜索'), findsOneWidget);
      expect(find.text('图谱检索'), findsOneWidget);
      expect(find.text('调用中'), findsAtLeastNWidgets(1));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final pendingParts = card?.snapshot?.messageParts.where((part) {
            return part.type == 'tool_call' && part.status == 'running';
          }).toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      expect(pendingParts.map((part) => part.toolId), [
        'semantic_search_current_book',
        'semantic_search_library',
        'notes_search',
        'memory_search',
        'concept_graph_search',
      ]);

      releaseEvidence.complete();
      await _finishLiveSeminarWidgetRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
        runFuture: runFuture,
      );
    },
  );

  testWidgets(
    'running Seminar chat card shows live role partial before completion',
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
      final partialEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarPendingLiveRoleService(
                partialEmitted: partialEmitted,
                releaseRole: releaseRole,
                currentBookEvidenceCount: 3,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'notes_search',
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await _waitForLiveSeminarSignal(tester, partialEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        expect(find.text('研讨流'), findsOneWidget);
        expect(find.text('批判者'), findsAtLeastNWidgets(1));
        expect(find.text('Partial critical response.'), findsOneWidget);
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final partialPart = card?.snapshot?.messageParts
            .singleWhere((part) => part.type == 'role_partial');
        expect(
          partialPart?.id,
          'seminar-chat-history:role-critical-0:delta:latest',
        );
        expect(partialPart?.roleId, 'critical');
        expect(partialPart?.label, '批判者');
        expect(partialPart?.text, 'Partial critical response.');
        final statusPart = card?.snapshot?.messageParts.singleWhere(
          (part) =>
              part.type == 'agent_status' &&
              part.agentRunId == 'seminar-chat-history:role-critical-0',
        );
        expect(statusPart?.label, 'role-running');
        expect(statusPart?.roleId, 'critical');
        expect(statusPart?.parentRunId, 'seminar-chat-history');
        expect(
            statusPart?.actionIds, containsAll(['wait-agent', 'close-agent']));
        expect(find.text('角色正在生成'), findsOneWidget);
        expect(find.text('等待角色'), findsOneWidget);
        expect(find.text('停止角色'), findsOneWidget);
        final runtimeState = container.read(
          aiSeminarRuntimeScopedProvider('seminar-chat-history'),
        );
        expect(
          runtimeState.session
              ?.roleProfileFor(AiSeminarRole.critical)
              ?.allowedToolIds,
          [
            'semantic_search_current_book',
            'notes_search',
          ],
        );
        final roleToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId == 'seminar-chat-history:role-critical-0',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(
          roleToolParts,
          hasLength(1),
          reason: card?.snapshot?.messageParts
              .map((part) => part.toJson())
              .toList(growable: false)
              .toString(),
        );
        final roleToolPart = roleToolParts.single;
        expect(roleToolPart.parentRunId, 'seminar-chat-history');
        expect(roleToolPart.toolId, 'semantic_search_current_book');
        expect(roleToolPart.query, '这个概念怎么理解？');
        expect(roleToolPart.resultCount, 3);
        expect(roleToolPart.roleIds, ['critical']);
        expect(
          roleToolPart.evidenceRefs.map((item) => item.id),
          ['e-live-role', 'e-live-role-2', 'e-live-role-3'],
        );
        expect(
          card?.snapshot?.messageParts
              .where((part) =>
                  part.agentRunId == 'seminar-chat-history:role-critical-0' &&
                  part.toolId == 'notes_search')
              .toList(growable: false),
          isEmpty,
        );
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card stops active main role natively',
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
      final partialEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarPendingLiveRoleService(
                partialEmitted: partialEmitted,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await _waitForLiveSeminarSignal(tester, partialEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        final closeFinder = find.byKey(
          const ValueKey(
            'seminar-chat-card-agent-action-close-agent-'
            'seminar-chat-history:role-critical-0',
          ),
        );
        expect(closeFinder, findsOneWidget);

        await tester.tap(closeFinder);
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        final runtimeState = container.read(
          aiSeminarRuntimeScopedProvider('seminar-chat-history'),
        );
        expect(runtimeState.status, AiSeminarRunStatus.cancelled);
        expect(find.text('研讨已停止'), findsOneWidget);
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'reading Seminar evidence tool calls hide library fallback tools',
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
      final partialEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarPendingLiveRoleService(
                partialEmitted: partialEmitted,
                releaseRole: releaseRole,
                includeLibraryEvidence: true,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'semantic_search_library',
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await _waitForLiveSeminarSignal(tester, partialEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final roleToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId == 'seminar-chat-history:role-critical-0',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(
          roleToolParts.map((part) => part.toolId),
          ['semantic_search_current_book'],
          reason: card?.snapshot?.messageParts
              .map((part) => part.toJson())
              .toList(growable: false)
              .toString(),
        );
        final evidenceToolParts = card?.snapshot?.messageParts
                .where(
                  (part) => part.type == 'tool_call' && part.agentRunId == null,
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(
          evidenceToolParts.map((part) => part.toolId),
          ['semantic_search_current_book'],
          reason: card?.snapshot?.messageParts
              .map((part) => part.toJson())
              .toList(growable: false)
              .toString(),
        );
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card shows true role agent tool calls from stream',
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
      final toolEventEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarLiveAgentToolCallService(
                toolEventEmitted: toolEventEmitted,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'notes_search',
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, toolEventEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(
          liveToolParts,
          hasLength(1),
          reason: card?.snapshot?.messageParts
              .map((part) => part.toJson())
              .toList(growable: false)
              .toString(),
        );
        final liveToolPart = liveToolParts.single;
        expect(liveToolPart.parentRunId, 'seminar-chat-history');
        expect(liveToolPart.status, 'completed');
        expect(liveToolPart.query, 'agency notes');
        expect(liveToolPart.resultCount, 1);
        expect(liveToolPart.roleIds, ['critical']);

        expect(find.text('研讨流'), findsOneWidget);
        expect(find.text('笔记搜索'), findsAtLeastNWidgets(1));
        expect(find.text('查询：agency notes'), findsOneWidget);
        expect(find.text('调用完成'), findsOneWidget);
        expect(find.text('Returned 1 note match.'), findsOneWidget);
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'restored Seminar card filters live role agent library fallback tools',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch1.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'Restored live role evidence.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final restoredRuntimeState = AiSeminarRuntimeState(
        status: AiSeminarRunStatus.completed,
        session: AiSeminarSessionContract(
          id: sessionId,
          question: '这个概念怎么理解？',
          bookId: 7,
          roles: const [AiSeminarRole.critical],
          roleProfiles: [
            AiSeminarRoleProfile(
              role: AiSeminarRole.critical,
              allowedToolIds: const [
                'semantic_search_current_book',
                'semantic_search_library',
                'notes_search',
              ],
            ),
          ],
          maxRounds: 1,
          createdAt: 1000,
        ),
        evidenceBundle: AiSeminarEvidenceBundle(
          query: '这个概念怎么理解？',
          evidence: [
            AiSeminarEvidence(
              id: 'e-restored-live-role',
              scope: AiSeminarEvidenceScope.currentBook,
              text: 'Restored live role evidence.',
              sourceRef: sourceRef,
            ),
          ],
        ),
        roleAgentToolCallEvents: [
          AgentRunEvent(
            eventId: '$sessionId:role-critical-0:tool:notes',
            runId: '$sessionId:role-critical-0',
            parentRunId: sessionId,
            type: AgentRunEventType.toolCall,
            createdAt: DateTime.utc(2026, 6, 5, 12),
            status: SubAgentRunStatus.completed,
            roleId: 'critical',
            nickname: 'Critical',
            toolId: 'notes_search',
            query: 'agency notes',
            result: 'Returned 1 note match.',
            resultCount: 1,
            roleIds: const ['critical'],
          ),
          AgentRunEvent(
            eventId: '$sessionId:role-critical-0:tool:library',
            runId: '$sessionId:role-critical-0',
            parentRunId: sessionId,
            type: AgentRunEventType.toolCall,
            createdAt: DateTime.utc(2026, 6, 5, 12, 0, 1),
            status: SubAgentRunStatus.completed,
            roleId: 'critical',
            nickname: 'Critical',
            toolId: 'semantic_search_library',
            query: '这个概念怎么理解？',
            result: 'Returned library fallback evidence.',
            resultCount: 1,
            roleIds: const ['critical'],
          ),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(restoredRuntimeState.toJson()),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final liveToolIds = card?.snapshot?.messageParts
              .where(
                (part) =>
                    part.type == 'tool_call' &&
                    part.agentRunId == '$sessionId:role-critical-0',
              )
              .map((part) => part.toolId)
              .toList(growable: false) ??
          const <String>[];
      expect(
        liveToolIds,
        ['notes_search'],
        reason: card?.snapshot?.messageParts
            .map((part) => part.toJson())
            .toList(growable: false)
            .toString(),
      );
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('笔记搜索'), findsAtLeastNWidgets(1));
      expect(find.text('书库语义检索'), findsNothing);
      expect(find.text('Returned library fallback evidence.'), findsNothing);
    },
  );

  testWidgets(
    'restored Seminar card keeps latest live role tool call lifecycle event',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const providerId = 'openai';
      const sessionId = 'seminar-chat-history';
      const toolEventId = '$sessionId:role-critical-0:tool:notes';
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
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch1.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'Restored lifecycle evidence.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final restoredRuntimeState = AiSeminarRuntimeState(
        status: AiSeminarRunStatus.completed,
        session: AiSeminarSessionContract(
          id: sessionId,
          question: '这个概念怎么理解？',
          bookId: 7,
          roles: const [AiSeminarRole.critical],
          roleProfiles: [
            AiSeminarRoleProfile(
              role: AiSeminarRole.critical,
              allowedToolIds: const [
                'semantic_search_current_book',
                'notes_search',
              ],
            ),
          ],
          maxRounds: 1,
          createdAt: 1000,
        ),
        evidenceBundle: AiSeminarEvidenceBundle(
          query: '这个概念怎么理解？',
          evidence: [
            AiSeminarEvidence(
              id: 'e-restored-lifecycle',
              scope: AiSeminarEvidenceScope.currentBook,
              text: 'Restored lifecycle evidence.',
              sourceRef: sourceRef,
            ),
          ],
        ),
        roleAgentToolCallEvents: [
          AgentRunEvent(
            eventId: toolEventId,
            runId: '$sessionId:role-critical-0',
            parentRunId: sessionId,
            type: AgentRunEventType.toolCall,
            createdAt: DateTime.utc(2026, 6, 5, 12),
            status: SubAgentRunStatus.running,
            roleId: 'critical',
            nickname: 'Critical',
            toolId: 'notes_search',
            query: 'agency notes',
            roleIds: const ['critical'],
          ),
          AgentRunEvent(
            eventId: toolEventId,
            runId: '$sessionId:role-critical-0',
            parentRunId: sessionId,
            type: AgentRunEventType.toolCall,
            createdAt: DateTime.utc(2026, 6, 5, 12, 0, 1),
            status: SubAgentRunStatus.completed,
            roleId: 'critical',
            nickname: 'Critical',
            toolId: 'notes_search',
            query: 'agency notes',
            result: 'Returned restored lifecycle note.',
            resultCount: 1,
            roleIds: const ['critical'],
          ),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(restoredRuntimeState.toJson()),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final liveToolParts = card?.snapshot?.messageParts
              .where(
                (part) =>
                    part.type == 'tool_call' &&
                    part.agentRunId == '$sessionId:role-critical-0' &&
                    part.toolId == 'notes_search',
              )
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      expect(
        liveToolParts,
        hasLength(1),
        reason: card?.snapshot?.messageParts
            .map((part) => part.toJson())
            .toList(growable: false)
            .toString(),
      );
      expect(liveToolParts.single.status, 'completed');
      expect(liveToolParts.single.text, 'Returned restored lifecycle note.');
      expect(find.text('笔记搜索'), findsAtLeastNWidgets(1));
      expect(find.text('调用完成'), findsAtLeastNWidgets(1));
      expect(find.text('Returned restored lifecycle note.'), findsOneWidget);
      expect(find.text('调用中'), findsNothing);
    },
  );

  testWidgets(
    'restored Seminar card prefers streamed role thinking over generic start',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const providerId = 'openai';
      const sessionId = 'seminar-chat-history';
      const roleRunId = '$sessionId:role-critical-0';
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
      final sourceRef = SourceRef(
        bookId: 7,
        href: 'Text/ch1.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'Restored thinking evidence.',
        sourceKind: SourceRefKind.currentBookRag,
      );
      final restoredRuntimeState = AiSeminarRuntimeState(
        status: AiSeminarRunStatus.running,
        session: AiSeminarSessionContract(
          id: sessionId,
          question: '这个概念怎么理解？',
          bookId: 7,
          roles: const [AiSeminarRole.critical],
          maxRounds: 1,
          createdAt: 1000,
        ),
        evidenceBundle: AiSeminarEvidenceBundle(
          query: '这个概念怎么理解？',
          evidence: [
            AiSeminarEvidence(
              id: 'e-restored-thinking',
              scope: AiSeminarEvidenceScope.currentBook,
              text: 'Restored thinking evidence.',
              sourceRef: sourceRef,
            ),
          ],
        ),
        activeRole: AiSeminarRole.critical,
        roleAgentThinkingEvents: [
          AgentRunEvent(
            eventId: '$roleRunId:thinking:start',
            runId: roleRunId,
            parentRunId: sessionId,
            type: AgentRunEventType.thinking,
            createdAt: DateTime.utc(2026, 6, 5, 12),
            roleId: 'critical',
            nickname: 'Critical',
            delta: '批判者正在准备基于证据发言。',
          ),
          AgentRunEvent(
            eventId: '$roleRunId:thinking:stream:0',
            runId: roleRunId,
            parentRunId: sessionId,
            type: AgentRunEventType.thinking,
            createdAt: DateTime.utc(2026, 6, 5, 12, 0, 1),
            roleId: 'critical',
            nickname: 'Critical',
            delta: 'Checking note and semantic evidence.',
          ),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
                '${Uri.encodeComponent(sessionId)}':
            jsonEncode(restoredRuntimeState.toJson()),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final thinkingParts = card?.snapshot?.messageParts
              .where(
                (part) =>
                    part.type == 'thinking' && part.agentRunId == roleRunId,
              )
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      expect(
        thinkingParts.map((part) => part.id),
        ['$roleRunId:thinking:stream:0'],
        reason: card?.snapshot?.messageParts
            .map((part) => part.toJson())
            .toList(growable: false)
            .toString(),
      );
      expect(thinkingParts.single.text, 'Checking note and semantic evidence.');
      expect(find.text('Checking note and semantic evidence.'), findsOneWidget);
      expect(find.text('批判者正在准备基于证据发言。'), findsNothing);
    },
  );

  testWidgets(
    'running Seminar chat card updates live role tool call status in place',
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
      final runningToolObserved = Completer<void>();
      final completedToolObserved = Completer<void>();
      final releaseTool = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarLiveAgentToolCallLifecycleService(
                runningToolObserved: runningToolObserved,
                completedToolObserved: completedToolObserved,
                releaseTool: releaseTool,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'notes_search',
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );

      try {
        await _waitForLiveSeminarSignal(tester, runningToolObserved.future);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        var card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        var liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.status, 'running');
        expect(liveToolParts.single.actionIds, [
          'wait-tool-call',
          'cancel-tool-call',
        ]);
        expect(find.text('笔记搜索'), findsAtLeastNWidgets(1));

        await tester.tap(find.byKey(const ValueKey(
          'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
        )));
        await tester.pump();
        expect(find.text('工具调用详情'), findsOneWidget);
        expect(find.text('调用中'), findsAtLeastNWidgets(1));
        expect(find.text('可用控制'), findsOneWidget);
        expect(find.text('等待工具调用'), findsOneWidget);
        expect(find.text('取消工具调用'), findsOneWidget);
        expect(
          find.byKey(const ValueKey(
            'seminar-chat-card-tool-action-wait-tool-call-'
            'seminar-chat-history:role-critical-0:tool:call-notes-lifecycle',
          )),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey(
            'seminar-chat-card-tool-action-cancel-tool-call-'
            'seminar-chat-history:role-critical-0:tool:call-notes-lifecycle',
          )),
          findsOneWidget,
        );

        releaseTool.complete();
        await _waitForLiveSeminarSignal(tester, completedToolObserved.future);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.status, 'completed');
        expect(liveToolParts.single.text, 'Returned lifecycle note.');
        expect(find.text('调用完成'), findsAtLeastNWidgets(1));
        expect(find.text('Returned lifecycle note.'), findsOneWidget);
      } finally {
        if (!releaseTool.isCompleted) releaseTool.complete();
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar live role tool call waits natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-live-wait-tool-call-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
      final runningToolObserved = Completer<void>();
      final completedToolObserved = Completer<void>();
      final releaseTool = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarLiveAgentToolCallLifecycleService(
                runningToolObserved: runningToolObserved,
                completedToolObserved: completedToolObserved,
                releaseTool: releaseTool,
                releaseRole: releaseRole,
                agentRunGraphStore: AgentRunGraphStore(),
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      late final Future<void> runFuture;
      await tester.runAsync(() async {
        runFuture = container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
            )
            .start(
              AiSeminarSessionContract(
                id: 'seminar-chat-history',
                question: '这个概念怎么理解？',
                bookId: 7,
                roles: const [AiSeminarRole.critical],
                roleProfiles: [
                  AiSeminarRoleProfile(
                    role: AiSeminarRole.critical,
                    allowedToolIds: const [
                      'semantic_search_current_book',
                      'notes_search',
                    ],
                  ),
                ],
                maxRounds: 1,
                createdAt: 1000,
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });

      try {
        final toolsTab = find.byKey(const ValueKey(
          'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
        ));
        for (var i = 0; i < 40 && toolsTab.evaluate().isEmpty; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
        }
        expect(toolsTab, findsOneWidget);
        await tester.tap(toolsTab);
        await tester.pump();

        final waitAction = find.byKey(const ValueKey(
          'seminar-chat-card-tool-action-wait-tool-call-'
          'seminar-chat-history:role-critical-0:tool:call-notes-lifecycle',
        ));
        for (var i = 0; i < 40 && waitAction.evaluate().isEmpty; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
        }
        expect(waitAction, findsOneWidget);

        final waitChip = tester.widget<ActionChip>(waitAction);
        await tester.runAsync(() async {
          waitChip.onPressed?.call();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final toolWaitTurns = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'reader_turn' &&
                      part.label == 'wait-tool-call' &&
                      part.agentRunId == 'seminar-chat-history:role-critical-0',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        final liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];

        expect(toolWaitTurns, hasLength(1));
        expect(toolWaitTurns.single.status, 'pending');
        expect(toolWaitTurns.single.toolId, 'notes_search');
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.actionIds, contains('cancel-tool-call'));
        expect(
            liveToolParts.single.actionIds, isNot(contains('wait-tool-call')));
        await tester.tap(find.byKey(const ValueKey(
          'seminar-chat-card-snapshot-tab-overview-seminar-chat-history',
        )));
        await tester.pump();
        expect(find.text('等待工具调用 · 批判者'), findsAtLeastNWidgets(1));
        expect(find.text('待处理'), findsAtLeastNWidgets(1));
      } finally {
        if (!releaseTool.isCompleted) releaseTool.complete();
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar live role tool call cancels current runtime natively',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory.systemTemp.createTempSync(
        'ai-chat-live-cancel-tool-call-widget-',
      );
      _mockPathProvider(tempDir.path);
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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
      final runningToolObserved = Completer<void>();
      final completedToolObserved = Completer<void>();
      final releaseTool = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarLiveAgentToolCallLifecycleService(
                runningToolObserved: runningToolObserved,
                completedToolObserved: completedToolObserved,
                releaseTool: releaseTool,
                releaseRole: releaseRole,
                agentRunGraphStore: AgentRunGraphStore(),
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final graphStore = AgentRunGraphStore();
      late final Future<void> runFuture;
      await tester.runAsync(() async {
        runFuture = container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
            )
            .start(
              AiSeminarSessionContract(
                id: 'seminar-chat-history',
                question: '这个概念怎么理解？',
                bookId: 7,
                roles: const [AiSeminarRole.critical],
                roleProfiles: [
                  AiSeminarRoleProfile(
                    role: AiSeminarRole.critical,
                    allowedToolIds: const [
                      'semantic_search_current_book',
                      'notes_search',
                    ],
                  ),
                ],
                maxRounds: 1,
                createdAt: 1000,
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });

      try {
        final toolsTab = find.byKey(const ValueKey(
          'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
        ));
        for (var i = 0; i < 40 && toolsTab.evaluate().isEmpty; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
        }
        expect(toolsTab, findsOneWidget);
        await tester.tap(toolsTab);
        await tester.pump();

        final cancelAction = find.byKey(
          const ValueKey(
            'seminar-chat-card-tool-action-cancel-tool-call-'
            'seminar-chat-history:role-critical-0:tool:call-notes-lifecycle',
          ),
        );
        for (var i = 0; i < 40 && cancelAction.evaluate().isEmpty; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
        }
        final cardBeforeCancel = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        expect(
          cancelAction,
          findsOneWidget,
          reason: cardBeforeCancel?.snapshot?.messageParts
              .map((part) => part.toJson())
              .toList(growable: false)
              .toString(),
        );

        final cancelChip = tester.widget<ActionChip>(cancelAction);
        await tester.runAsync(() async {
          cancelChip.onPressed?.call();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final runtimeState = container.read(
          aiSeminarRuntimeScopedProvider('seminar-chat-history'),
        );
        expect(runtimeState.status, AiSeminarRunStatus.cancelled);

        final childRun = await tester.runAsync<AgentRunRecord?>(
          () => graphStore.getRun('seminar-chat-history:role-critical-0'),
        );
        expect(childRun?.status, SubAgentRunStatus.shutdown);

        final events = await tester.runAsync<List<AgentRunEvent>>(
          () => graphStore.listEvents('seminar-chat-history:role-critical-0'),
        );
        final toolEvent = events!.singleWhere(
          (event) =>
              event.eventId ==
              'seminar-chat-history:role-critical-0:tool:call-notes-lifecycle',
        );
        expect(toolEvent.status, SubAgentRunStatus.shutdown);

        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.status, 'shutdown');
        expect(liveToolParts.single.actionIds, isEmpty);
        expect(find.text('已停止'), findsWidgets);
        expect(find.text('可用控制'), findsNothing);
      } finally {
        if (!releaseTool.isCompleted) releaseTool.complete();
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card updates live role tool call errors in place',
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
      final runningToolObserved = Completer<void>();
      final erroredToolObserved = Completer<void>();
      final releaseTool = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarLiveAgentToolCallErrorLifecycleService(
                runningToolObserved: runningToolObserved,
                erroredToolObserved: erroredToolObserved,
                releaseTool: releaseTool,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'notes_search',
                  ],
                ),
              ],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );

      try {
        await _waitForLiveSeminarSignal(tester, runningToolObserved.future);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        var card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        var liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.status, 'running');

        releaseTool.complete();
        await _waitForLiveSeminarSignal(tester, erroredToolObserved.future);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        liveToolParts = card?.snapshot?.messageParts
                .where(
                  (part) =>
                      part.type == 'tool_call' &&
                      part.agentRunId ==
                          'seminar-chat-history:role-critical-0' &&
                      part.toolId == 'notes_search',
                )
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(liveToolParts, hasLength(1));
        expect(liveToolParts.single.status, 'errored');
        expect(liveToolParts.single.text, 'notes index unavailable');
        await tester.tap(find.byKey(const ValueKey(
          'seminar-chat-card-snapshot-tab-tools-seminar-chat-history',
        )));
        await tester.pump();
        expect(find.text('工具调用详情'), findsOneWidget);
        expect(find.text('调用失败'), findsOneWidget);
        expect(find.text('notes index unavailable'), findsOneWidget);
      } finally {
        if (!releaseTool.isCompleted) releaseTool.complete();
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card shows role thinking before first partial',
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
      final roleStreamEntered = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarWaitingLiveRoleService(
                roleStreamEntered: roleStreamEntered,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, roleStreamEntered.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        expect(find.text('研讨流'), findsOneWidget);
        expect(find.text('思考'), findsWidgets);
        expect(find.text('批判者正在准备基于证据发言。'), findsOneWidget);
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final thinkingPart = card?.snapshot?.messageParts.singleWhere(
          (part) =>
              part.type == 'thinking' &&
              part.id == 'seminar-chat-history:role-critical-0:thinking:start',
        );
        expect(thinkingPart?.roleId, 'critical');
        expect(thinkingPart?.label, '批判者');
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card shows streamed role thinking summaries',
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
      final thinkingEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarStreamedThinkingLiveRoleService(
                thinkingEmitted: thinkingEmitted,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, thinkingEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        expect(find.text('研讨流'), findsOneWidget);
        expect(find.text('思考'), findsWidgets);
        expect(
            find.text('Checking note and semantic evidence.'), findsOneWidget);
        final card = container
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(1);
        final thinkingParts = card?.snapshot?.messageParts
                .where((part) =>
                    part.type == 'thinking' &&
                    part.agentRunId == 'seminar-chat-history:role-critical-0')
                .toList(growable: false) ??
            const <AiSeminarRunCardMessagePart>[];
        expect(
          thinkingParts.map((part) => part.id),
          ['seminar-chat-history:role-critical-0:thinking:stream:0'],
        );
        final thinkingPart = card?.snapshot?.messageParts.singleWhere(
          (part) =>
              part.type == 'thinking' &&
              part.id ==
                  'seminar-chat-history:role-critical-0:thinking:stream:0',
        );
        expect(thinkingPart?.roleId, 'critical');
        expect(thinkingPart?.text, 'Checking note and semantic evidence.');
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
    },
  );

  testWidgets(
    'running Seminar chat card cancels active run natively',
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
      final partialEmitted = Completer<void>();
      final releaseRole = Completer<void>();

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
              _seminarPendingLiveRoleService(
                partialEmitted: partialEmitted,
                releaseRole: releaseRole,
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final runFuture = container
          .read(aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier)
          .start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: const [AiSeminarRole.critical],
              maxRounds: 1,
              createdAt: 1000,
            ),
          );
      await _waitForLiveSeminarSignal(tester, partialEmitted.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      try {
        expect(
          find.byKey(
            const ValueKey('seminar-chat-card-cancel-seminar-chat-history'),
          ),
          findsOneWidget,
        );
        expect(find.text('取消研讨'), findsOneWidget);

        await tester.tap(find.byKey(
          const ValueKey('seminar-chat-card-cancel-seminar-chat-history'),
        ));
        await tester.pump();

        final runtimeState = container.read(
          aiSeminarRuntimeScopedProvider('seminar-chat-history'),
        );
        expect(runtimeState.status, AiSeminarRunStatus.cancelled);
        expect(runtimeState.activeRole, isNull);
      } finally {
        if (!releaseRole.isCompleted) releaseRole.complete();
        await _finishLiveSeminarWidgetRun(
          tester: tester,
          container: container,
          sessionId: 'seminar-chat-history',
          runFuture: runFuture,
        );
      }
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

      expect(find.text('研讨流'), findsOneWidget);
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
      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('还有 2 个研讨片段可在分类视图中查看。'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-disagreements-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
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
    'persisted Seminar chat card renders Review triage message parts',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-part-');
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useReviewTriageMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('中风险'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
      expect(find.text('送入异常中心'), findsOneWidget);
      expect(find.text('medium'), findsNothing);
      expect(find.text('send-to-review'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-review-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('异常处理预览'), findsOneWidget);
      expect(find.text('Recovered review synthesis.'), findsOneWidget);
      expect(find.text('可追踪证据：3 条'), findsOneWidget);
      expect(find.text('AI 预审建议'), findsOneWidget);
      expect(find.text('建议送审：未解决分歧需要人工确认。'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('中风险'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
      expect(find.text('送入异常中心'), findsOneWidget);
      expect(find.text('异常原因'), findsOneWidget);
      expect(find.text('存在未解决分歧：1 项'), findsOneWidget);
      expect(find.text('异常送审内容'), findsOneWidget);
      expect(find.text('知识卡候选：1 项'), findsOneWidget);
      expect(find.text('Recovered exception card'), findsOneWidget);
      expect(find.text('候选证据'), findsOneWidget);
      expect(find.text('Recovered card evidence.'), findsOneWidget);
      expect(find.text('复习候选：1 项'), findsOneWidget);
      expect(find.text('Recovered review question?'), findsOneWidget);
      expect(find.text('综合证据'), findsOneWidget);
      expect(find.text('Recovered synthesis evidence.'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar review triage only card exposes review tab',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-only-');
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useReviewTriageOnlyMessagePartsOnly: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('研讨流'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('中风险'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
      expect(find.text('送入异常中心'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-review-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('异常处理预览'), findsOneWidget);
      expect(find.text('可追踪证据：0 条'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted Seminar review triage shows all candidate items',
    (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-items-');
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
      container.read(aiChatProvider.notifier).loadHistoryEntry(
            _seminarCardHistoryEntry(
              useReviewTriageMessagePartsOnly: true,
              useMultipleReviewTriageCandidates: true,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-review-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('异常处理预览'), findsOneWidget);
      expect(find.text('知识卡候选：4 项'), findsOneWidget);
      expect(find.text('Recovered exception card 1'), findsOneWidget);
      expect(find.text('Recovered exception card 4 should stay visible'),
          findsOneWidget);
      expect(find.text('复习候选：4 项'), findsOneWidget);
      expect(find.text('Recovered review question 1?'), findsOneWidget);
      expect(find.text('Recovered review question 4 should stay visible?'),
          findsOneWidget);
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

      unawaited(
        container
            .read(
              aiSeminarRuntimeScopedProvider('seminar-chat-history').notifier,
            )
            .start(
              AiSeminarSessionContract(
                id: 'seminar-chat-history',
                question: '这个概念怎么理解？',
                bookId: 7,
                roles: AiSeminarRole.defaultRoles,
                createdAt: 1000,
              ),
            ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );
      final sendToReviewButton = find.widgetWithText(OutlinedButton, '异常送审');
      expect(sendToReviewButton, findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-snapshot-tab-review-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('异常处理预览'), findsOneWidget);
      expect(find.text('只在低置信、冲突或来源异常时发送到 Review Inbox'), findsOneWidget);
      expect(find.text('AI 预审建议'), findsOneWidget);
      expect(find.text('建议送审：未解决分歧需要人工确认。'), findsOneWidget);
      expect(find.text('AI 风险等级'), findsOneWidget);
      expect(find.text('中风险'), findsOneWidget);
      expect(find.text('建议动作'), findsOneWidget);
      expect(find.text('送入异常中心'), findsOneWidget);
      expect(find.text('异常原因'), findsOneWidget);
      expect(find.text('存在未解决分歧：1 项'), findsOneWidget);
      expect(find.text('包含知识卡候选：1 项'), findsOneWidget);
      expect(find.text('包含复习候选：1 项'), findsOneWidget);
      expect(find.text('综合总结'), findsOneWidget);
      expect(find.text('synthesizer response'), findsOneWidget);
      expect(find.text('可追踪证据：5 条'), findsOneWidget);
      expect(find.text('异常送审内容'), findsOneWidget);
      expect(find.text('综合总结：1 项'), findsOneWidget);
      expect(find.text('知识卡候选：1 项'), findsOneWidget);
      expect(find.text('Exception card candidate'), findsOneWidget);
      expect(find.text('候选证据'), findsWidgets);
      expect(find.text('Additional source passage 2.'), findsWidgets);
      expect(find.text('Additional source passage 3.'), findsWidgets);
      expect(find.text('Unused source passage 5.'), findsWidgets);
      expect(find.text('复习候选：1 项'), findsOneWidget);
      expect(find.text('What boundary should be reviewed?'), findsOneWidget);
      expect(find.text('综合证据'), findsOneWidget);
      expect(find.text('The source passage.'), findsOneWidget);
      expect(find.text('Additional source passage 4.'), findsWidgets);
      expect(find.text('普通学习保存请优先使用知识卡、复习或我的图谱。'), findsOneWidget);
      final reviewCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final reviewTriageParts = reviewCard?.snapshot?.messageParts
              .where((part) => part.type == 'review_triage')
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[];
      expect(
        reviewTriageParts.map((part) => part.label),
        containsAll([
          'reason',
          'ai-suggestion',
          'knowledge-card',
          'spaced-review',
        ]),
      );
      expect(
        reviewTriageParts.map((part) => part.text),
        containsAll([
          '存在未解决分歧：1 项',
          '建议送审：未解决分歧需要人工确认。',
          'Exception card candidate',
          'What boundary should be reviewed?',
        ]),
      );
      final cardPart = reviewTriageParts
          .singleWhere((part) => part.label == 'knowledge-card');
      expect(
        cardPart.evidenceRefs.map((item) => item.snippet),
        containsAll([
          'Additional source passage 2.',
          'Additional source passage 3.',
          'Unused source passage 5.',
        ]),
      );
      final reviewQuestionPart = reviewTriageParts
          .singleWhere((part) => part.label == 'spaced-review');
      expect(
        reviewQuestionPart.evidenceRefs.map((item) => item.snippet),
        contains('Additional source passage 4.'),
      );

      await tester.ensureVisible(sendToReviewButton);
      await tester.pump();
      await tester.tap(sendToReviewButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

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
      final sentReviewCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final artifactActionsPart =
          sentReviewCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        artifactActionsPart?.actionIds,
        contains('sent-to-review'),
      );
      expect(
        artifactActionsPart?.actionIds,
        isNot(contains('send-to-review')),
      );
      expect(
        artifactActionsPart?.text,
        contains('异常已送审'),
      );
      expect(find.widgetWithText(OutlinedButton, '异常送审'), findsNothing);
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
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );
      expect(
        find.text('保存知识卡'),
        findsAtLeastNWidgets(1),
      );

      await _ensureVisibleAndTap(
        tester,
        find.text('保存知识卡').last,
      );
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
      final savedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final artifactActionsPart = savedCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        artifactActionsPart?.actionIds,
        containsAll({'knowledge-card-saved', 'undo-knowledge-card'}),
      );
      expect(
        artifactActionsPart?.actionIds,
        isNot(contains('save-knowledge-card')),
      );
      expect(
        artifactActionsPart?.actionIds,
        isNot(contains('edit-knowledge-card')),
      );
      expect(
        artifactActionsPart?.text,
        contains('知识卡已保存'),
      );
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      expect(find.text('编辑后保存'), findsOneWidget);

      await _ensureVisibleAndTap(tester, find.text('编辑后保存'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('编辑知识卡'),
        ),
        findsOneWidget,
      );
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
      documentPath = tempDir.path;
      addTearDown(() {
        _mockPathProvider(null);
        documentPath = '';
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await _ensureVisibleAndTap(
        tester,
        find.text('保存知识卡').last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        hasLength(1),
      );
      expect(find.text('撤销保存'), findsOneWidget);

      await _ensureVisibleAndTap(tester, find.text('撤销保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        isEmpty,
      );
      expect(await reviewStore.list(), isEmpty);
      expect(
        find.text('保存知识卡'),
        findsAtLeastNWidgets(1),
      );
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      expect(
        find.text('保存知识卡'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('编辑后保存'), findsOneWidget);
      expect(find.text('加入复习'), findsAtLeastNWidgets(1));
      expect(
        find.text('加入我的图谱'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('忽略'), findsOneWidget);

      await _ensureVisibleAndTap(tester, find.text('忽略'));
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
      final ignoredCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final ignoredActionsPart =
          ignoredCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        ignoredActionsPart?.actionIds,
        containsAll({'artifact-actions-ignored', 'restore-artifact-actions'}),
      );
      expect(
        ignoredActionsPart?.actionIds,
        isNot(contains('ignore-artifact-actions')),
      );
      expect(
        ignoredActionsPart?.text,
        contains('沉淀建议已忽略'),
      );

      await _ensureVisibleAndTap(tester, find.text('恢复操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text('保存知识卡'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('编辑后保存'), findsOneWidget);
      expect(find.text('加入复习'), findsAtLeastNWidgets(1));
      expect(
        find.text('加入我的图谱'),
        findsAtLeastNWidgets(1),
      );
      final restoredCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final restoredActionsPart =
          restoredCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        restoredActionsPart?.actionIds,
        contains('ignore-artifact-actions'),
      );
      expect(
        restoredActionsPart?.actionIds,
        isNot(contains('artifact-actions-ignored')),
      );
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );
      expect(find.text('加入复习'), findsAtLeastNWidgets(1));

      await _ensureVisibleAndTap(
        tester,
        find.text('加入复习').last,
      );
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
      final savedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final artifactActionsPart = savedCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        artifactActionsPart?.actionIds,
        containsAll({'spaced-review-added', 'undo-spaced-review'}),
      );
      expect(
        artifactActionsPart?.actionIds,
        isNot(contains('add-spaced-review')),
      );
      expect(
        artifactActionsPart?.text,
        contains('复习已加入'),
      );
      expect(find.text('撤销复习'), findsAtLeastNWidgets(1));
      expect(find.textContaining('已加入复习'), findsOneWidget);

      await _ensureVisibleAndTap(tester, find.text('撤销复习').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(await spacedReviewStore.list(dueOnly: false), isEmpty);
      expect(await reviewStore.list(), isEmpty);
      expect(find.text('加入复习'), findsAtLeastNWidgets(1));
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );
      expect(
        find.text('加入我的图谱'),
        findsAtLeastNWidgets(1),
      );

      await _ensureVisibleAndTap(
        tester,
        find.text('加入我的图谱').last,
      );
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
      final savedCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final artifactActionsPart = savedCard?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'artifact_actions',
      );
      expect(
        artifactActionsPart?.actionIds,
        containsAll({'concept-graph-added', 'undo-concept-graph'}),
      );
      expect(
        artifactActionsPart?.actionIds,
        isNot(contains('add-concept-graph')),
      );
      expect(
        artifactActionsPart?.text,
        contains('图谱已加入'),
      );
      expect(find.text('撤销图谱'), findsAtLeastNWidgets(1));
      expect(find.textContaining('已加入我的图谱'), findsOneWidget);

      await _ensureVisibleAndTap(tester, find.text('撤销图谱').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(await graphStore.listNodes(), isEmpty);
      expect(await reviewStore.list(), isEmpty);
      expect(
        find.text('加入我的图谱'),
        findsAtLeastNWidgets(1),
      );
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );
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
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

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
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final readerPart = card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'reader_turn');
      expect(readerPart?.id, state.directorState!.lastUserIntervention!.id);
      expect(readerPart?.roleId, 'critical');
      expect(readerPart?.label, 'ask-role');
      expect(readerPart?.text, '请批判者针对此处范围争议继续反驳。');
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      final askUserState = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(askUserState.status, AiSeminarRunStatus.completed);
      expect(
        askUserState.directorState!.nextIntent,
        AiSeminarDirectorNextIntent.askUser,
      );
      expect(askUserState.directorState!.needsUserInput, true);
      expect(find.text('读者参与'), findsOneWidget);
      expect(find.text('主持人正在等待你的回应'), findsOneWidget);
      expect(
        find.text('Which interpretation should the reader test next?'),
        findsAtLeastNWidgets(1),
      );
      final askUserCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final directorPart = askUserCard?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'director_state');
      expect(directorPart?.id, 'director-seminar-chat-history');
      expect(directorPart?.label, 'ask-user');
      expect(
        directorPart?.text,
        'Which interpretation should the reader test next?',
      );
      final composerPart = askUserCard?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'reader_composer');
      expect(composerPart?.id, 'composer-seminar-chat-history');
      expect(composerPart?.label, 'ask-user');
      expect(
        composerPart?.text,
        'Which interpretation should the reader test next?',
      );
      expect(composerPart?.defaultActionId, 'ask-role');
      expect(composerPart?.defaultRoleId, 'critical');
      expect(
        composerPart?.actionIds,
        ['ask-role', 'refresh-evidence', 'synthesize', 'clarify'],
      );
      expect(composerPart?.roleIds, ['critical', 'supportive']);

      await tester.enterText(
        find.byKey(
          const ValueKey('seminar-chat-card-reply-seminar-chat-history'),
        ),
        '我想先让批判者回应这个开放问题。',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-role-seminar-chat-history'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('支持者').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      final draftCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final draftComposerPart = draftCard?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'reader_composer');
      expect(draftComposerPart?.draftText, '我想先让批判者回应这个开放问题。');
      expect(draftComposerPart?.defaultRoleId, 'critical');
      expect(draftComposerPart?.selectedRoleId, 'supportive');
      expect(draftComposerPart?.selectedActionId, 'ask-role');
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-ask-role-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(state.turns.last.id, 'turn-supportive-follow-up');
      expect(state.turns.last.responseText, 'supportive follow-up response');
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.askRole,
      );
      expect(
        state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.supportive,
      );
      expect(state.directorState!.lastUserIntervention!.isEvidence, false);
      expect(
        prompts.last,
        contains('Reader intervention: 我想先让批判者回应这个开放问题。'),
      );
      expect(find.text('supportive follow-up response'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar askUser composer persists selected action and submits it',
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-action-refresh-evidence-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final draftCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final draftComposerPart = draftCard?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'reader_composer');
      expect(draftComposerPart?.draftText, isNull);
      expect(draftComposerPart?.defaultActionId, 'ask-role');
      expect(draftComposerPart?.selectedActionId, 'refresh-evidence');
      expect(draftComposerPart?.selectedRoleId, 'critical');

      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-ask-role-seminar-chat-history'),
        ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.refreshEvidence,
      );
      expect(state.directorState!.lastUserIntervention!.targetRole, isNull);
      expect(state.directorState!.lastUserIntervention!.text, '');
      expect(state.directorState!.evidenceRefreshCount, 1);
    },
  );

  testWidgets(
    'Seminar askUser composer persists synthesize Director end message part',
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-action-synthesize-seminar-chat-history',
          ),
        ),
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
      expect(
        state.directorState!.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.synthesize,
      );
      expect(state.directorState!.lastUserIntervention!.targetRole, isNull);
      expect(state.directorState!.nextIntent, AiSeminarDirectorNextIntent.end);
      expect(find.text('主持人已完成本轮研讨'), findsOneWidget);
      expect(find.text('synthesizer response'), findsAtLeastNWidgets(1));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final directorPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'director_state' && part.label == 'end',
      );
      expect(directorPart?.id, 'director-seminar-chat-history');
      expect(directorPart?.label, 'end');
      expect(directorPart?.text, 'synthesizer response');
    },
  );

  testWidgets(
    'Seminar askUser composer shows synthesize Director cue before completion',
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-action-synthesize-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('seminar-chat-card-ask-role-seminar-chat-history'),
        ),
      );
      for (var i = 0; i < 125; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        if (find.text('主持人准备整理总结').evaluate().isNotEmpty) {
          break;
        }
      }

      final cueCard = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(
        cueCard?.snapshot?.messageParts
            .map((part) => '${part.type}:${part.label}:${part.text}')
            .toList(growable: false),
        contains('director_state:synthesize:null'),
      );
      expect(find.text('主持人准备整理总结'), findsOneWidget);
      final cueParts = cueCard?.snapshot?.messageParts
          .where(
            (part) =>
                part.type == 'director_state' && part.label == 'synthesize',
          )
          .toList(growable: false);
      expect(cueParts, hasLength(1));
      final cuePart = cueParts?.single;
      expect(cuePart?.id, 'director-seminar-chat-history');
      expect(cuePart?.text, isNull);

      await tester.pump(const Duration(milliseconds: 300));

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(state.directorState!.nextIntent, AiSeminarDirectorNextIntent.end);
      expect(find.text('主持人已完成本轮研讨'), findsOneWidget);
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

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
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

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
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rebuttalPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'disagreement_rebuttal',
      );
      expect(rebuttalPart?.id, 'turn-critical-follow-up');
      expect(rebuttalPart?.roleId, 'critical');
      expect(rebuttalPart?.label, 'Scope remains disputed.');
      expect(rebuttalPart?.text, 'critical follow-up response');
      expect(rebuttalPart?.evidenceRefs.single.id, 'e1');
      expect(
        prompts.last,
        contains('Reader intervention: 围绕分歧继续反驳：Scope remains disputed.'),
      );
    },
  );

  testWidgets(
    'Seminar chat card exposes actions for each disagreement',
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
              _seminarCardDisagreementService(
                prompts,
                includeSecondDisagreement: true,
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      expect(find.text('分歧继续讨论'), findsNWidgets(2));
      expect(
          find.text('Terminology remains disputed.'), findsAtLeastNWidgets(1));

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-ask-critical-disagreement-seminar-chat-history-1',
          ),
        ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final state = container.read(
        aiSeminarRuntimeScopedProvider('seminar-chat-history'),
      );
      expect(
        state.directorState!.lastUserIntervention!.text,
        '围绕分歧继续反驳：Terminology remains disputed.',
      );
      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rebuttalPart = card?.snapshot?.messageParts.singleWhere(
        (part) => part.type == 'disagreement_rebuttal',
      );
      expect(rebuttalPart?.label, 'Terminology remains disputed.');
      expect(
        prompts.last,
        contains(
          'Reader intervention: 围绕分歧继续反驳：Terminology remains disputed.',
        ),
      );
    },
  );

  testWidgets(
    'restored Seminar card exposes actions for all generated disagreements',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final runtimeState =
          _seminarRuntimeStateWithMultipleActionDisagreements(sessionId);

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
        '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
            '${Uri.encodeComponent(sessionId)}': jsonEncode(
          runtimeState.toJson(),
        ),
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
            _seminarCardHistoryEntry(includeSnapshot: false),
          );
      await tester.pump();

      for (var i = 0; i < 20; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        if (find.text('分歧继续讨论').evaluate().length == 4) break;
      }

      expect(find.text('分歧继续讨论'), findsNWidgets(4));
      expect(
        find.text('Interpretation remains disputed.'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-ask-critical-disagreement-seminar-chat-history-3',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-refresh-disagreement-seminar-chat-history-3',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Seminar chat card preserves multiple disagreement rebuttal message parts',
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
              _seminarCardDisagreementService(
                prompts,
                includeSecondDisagreement: true,
                uniqueFollowUpTurnIds: true,
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-ask-critical-disagreement-seminar-chat-history',
          ),
        ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'seminar-chat-card-ask-critical-disagreement-seminar-chat-history-1',
          ),
        ),
      );
      await tester.pump();
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      final rebuttalParts = card?.snapshot?.messageParts
          .where((part) => part.type == 'disagreement_rebuttal')
          .toList(growable: false);
      expect(rebuttalParts, hasLength(2));
      expect(
        rebuttalParts?.map((part) => part.id),
        containsAll([
          'turn-critical-follow-up-1',
          'turn-critical-follow-up-2',
        ]),
      );
      expect(
        rebuttalParts?.map((part) => part.label),
        containsAll([
          'Scope remains disputed.',
          'Terminology remains disputed.',
        ]),
      );
      expect(
        prompts.where((prompt) => prompt.contains('Reader intervention:')),
        hasLength(2),
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

      await _startAndWaitForReadySeminarCardRun(
        tester: tester,
        container: container,
      );

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
      await _waitForReadySeminarCardRun(
        tester: tester,
        container: container,
        sessionId: 'seminar-chat-history',
      );

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

AiSeminarRuntimeState _seminarRuntimeStateWithMultipleGeneratedRebuttals(
  String sessionId,
) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final evidenceBundle = AiSeminarEvidenceBundle(
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
    status: AiSeminarRunStatus.completed,
    evidenceBundle: evidenceBundle,
    turns: [
      for (var i = 1; i <= 5; i += 1)
        AiSeminarRoleTurn(
          id: 'turn-critical-follow-up-$i',
          role: AiSeminarRole.critical,
          prompt:
              'Reader intervention: 围绕分歧继续反驳：Runtime disagreement target $i.',
          responseText: 'Runtime rebuttal $i.',
          evidenceRefIds: const ['e1'],
        ),
    ],
    completedAt: 2000,
  );
}

AiSeminarRuntimeState _seminarRuntimeStateWithMultipleGeneratedRoleTurns(
  String sessionId,
) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final evidenceBundle = AiSeminarEvidenceBundle(
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
    status: AiSeminarRunStatus.completed,
    evidenceBundle: evidenceBundle,
    turns: [
      for (var i = 1; i <= 5; i += 1)
        AiSeminarRoleTurn(
          id: 'turn-critical-$i',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt $i',
          responseText: 'Runtime role response $i.',
          evidenceRefIds: const ['e1'],
        ),
    ],
    completedAt: 2000,
  );
}

AiSeminarRuntimeState _seminarRuntimeStateWithMultipleGeneratedEvidence(
  String sessionId,
) {
  final evidence = [
    for (var i = 1; i <= 5; i += 1)
      AiSeminarEvidence(
        id: 'e$i',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Runtime evidence $i.',
        sourceRef: SourceRef(
          bookId: 7,
          href: 'Text/ch$i.xhtml',
          cfi: 'epubcfi(/6/${8 + i})',
          jumpLink:
              'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/${8 + i}%29',
          sourceTextSnippet: 'Runtime evidence $i.',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ),
  ];
  final evidenceBundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: evidence,
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
    status: AiSeminarRunStatus.completed,
    evidenceBundle: evidenceBundle,
    turns: const [
      AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'critical prompt',
        responseText: 'critical response',
        evidenceRefIds: ['e1', 'e2', 'e3', 'e4', 'e5'],
      ),
    ],
    completedAt: 2000,
  );
}

AiSeminarRuntimeState _seminarRuntimeStateWithMultipleGeneratedToolCalls(
  String sessionId,
) {
  final evidence = [
    for (final scope in AiSeminarEvidenceScope.values)
      AiSeminarEvidence(
        id: 'e-${scope.asString}',
        scope: scope,
        text: 'Runtime ${scope.asString} evidence.',
        sourceRef: SourceRef(
          bookId: 7,
          href: 'Text/${scope.asString}.xhtml',
          cfi: 'epubcfi(/6/${8 + scope.index})',
          jumpLink:
              'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/${8 + scope.index}%29',
          sourceTextSnippet: 'Runtime ${scope.asString} evidence.',
          sourceKind: switch (scope) {
            AiSeminarEvidenceScope.library => SourceRefKind.libraryRag,
            AiSeminarEvidenceScope.notes => SourceRefKind.note,
            AiSeminarEvidenceScope.memory => SourceRefKind.memory,
            _ => SourceRefKind.currentBookRag,
          },
        ),
      ),
  ];
  final evidenceBundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: evidence,
  );
  return AiSeminarRuntimeState.initial().copyWith(
    session: AiSeminarSessionContract(
      id: sessionId,
      question: '这个概念怎么理解？',
      bookId: 7,
      scopes: AiSeminarEvidenceScope.values,
      billingContext: const AiSeminarBillingContext(
        providerId: 'openai',
        providerName: 'OpenAI',
        providerType: 'openai',
        modelId: 'gpt-test',
      ),
    ),
    status: AiSeminarRunStatus.completed,
    evidenceBundle: evidenceBundle,
    turns: [
      AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'critical prompt',
        responseText: 'critical response',
        evidenceRefIds: evidence.map((item) => item.id).toList(growable: false),
      ),
    ],
    completedAt: 2000,
  );
}

AiSeminarRuntimeState _seminarRuntimeStateWithMultipleActionDisagreements(
  String sessionId,
) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  const disagreements = [
    'Scope remains disputed.',
    'Terminology remains disputed.',
    'Evidence priority remains disputed.',
    'Interpretation remains disputed.',
  ];
  final evidenceBundle = AiSeminarEvidenceBundle(
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
    status: AiSeminarRunStatus.completed,
    evidenceBundle: evidenceBundle,
    turns: [
      AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'critical prompt',
        responseText: 'critical response',
        evidenceRefIds: const ['e1'],
        whiteboardEntries: [
          for (var i = 0; i < disagreements.length; i += 1)
            AiSeminarWhiteboardEntry(
              id: 'action-disagreement-${i + 1}',
              kind: AiSeminarWhiteboardKind.disagreement,
              text: disagreements[i],
              role: AiSeminarRole.critical,
              evidenceRefIds: const ['e1'],
            ),
        ],
      ),
    ],
    synthesis: AiSeminarSynthesis(
      summary: 'Synthesis with multiple disagreements.',
      supportiveView: 'supportive view',
      criticalView: 'critical view',
      disagreements: disagreements,
      evidenceRefIds: const ['e1'],
      evidence: evidenceBundle.evidence,
    ),
    completedAt: 2000,
  );
}

AiChatHistoryEntry _seminarCardHistoryEntry({
  bool includeSnapshot = true,
  String? extraLegacyDisagreement,
  List<AiSeminarRoleProfile> roleProfiles = const <AiSeminarRoleProfile>[],
  bool includeRoleEvidenceRefs = false,
  bool includeSnapshotSourceRef = false,
  bool includeUnavailableSnapshotSourceRef = false,
  bool includeToolCalls = false,
  bool useSnapshotMultipleEvidenceRefs = false,
  bool useSnapshotMultipleToolCalls = false,
  bool useRoleMessagePartsOnly = false,
  bool useRoleMultipleEvidenceRefs = false,
  bool useRolePartialMessagePartsOnly = false,
  bool useLegacyMultipleRoleTurnMessageParts = false,
  bool useLegacyMultipleRolePartialMessageParts = false,
  bool useToolCallMessagePartsOnly = false,
  bool useParentEvidenceToolCallMessageParts = false,
  bool useToolCallMultipleEvidenceRefs = false,
  String? toolCallMessagePartStatus,
  int? toolCallMessagePartStartedAt,
  int? toolCallMessagePartCompletedAt,
  List<String> toolCallMessagePartActionIds = const <String>[],
  bool includeLibraryFallbackToolCallMessagePart = false,
  bool useArtifactActionsMessagePartsOnly = false,
  bool useSourceMissingArtifactActionsMessagePartsOnly = false,
  bool usePendingInitArtifactActionsMessagePartsOnly = false,
  bool useErroredArtifactActionsMessagePartsOnly = false,
  bool useMissingArtifactActionsMessagePartsOnly = false,
  bool useCancelledArtifactActionsMessagePartsOnly = false,
  bool useEvidenceMessagePartsOnly = false,
  bool useEvidenceBundleMessagePartType = false,
  bool useEvidenceMultipleRefs = false,
  bool useReaderTurnMessagePartsOnly = false,
  bool useToolWaitReaderTurnMessagePartsOnly = false,
  bool useLegacyMultipleReaderTurnMessageParts = false,
  bool usePendingReaderTurnMessagePartsOnly = false,
  bool usePendingInitReaderTurnMessagePartsOnly = false,
  bool useCancelledReaderTurnMessagePartsOnly = false,
  String cancelledReaderTurnStatus = 'cancelled',
  bool usePendingWaitReaderTurnMessagePartsOnly = false,
  bool usePendingRetryReaderTurnMessagePartsOnly = false,
  bool useDirectorStateMessagePartsOnly = false,
  bool useLegacyMultipleDirectorStateMessageParts = false,
  bool useLegacyMultipleReaderComposerMessageParts = false,
  bool useRoleStatusMessagePartsOnly = false,
  bool useRoleStatusAgentMetadataOnly = false,
  bool useAgentStatusMessagePartsOnly = false,
  bool useLegacyMultipleAgentStatusMessageParts = false,
  List<String>? agentStatusAllowedToolIds,
  String agentStatusLabel = 'role-running',
  String agentStatusText = 'Critical is running.',
  List<String> agentStatusActionIds = const ['wait-agent', 'close-agent'],
  bool keepEvidenceForToolCallMessageParts = false,
  bool useReaderComposerMessagePartsOnly = false,
  bool useSynthesisMessagePartsOnly = false,
  bool useDisagreementMessagePartsOnly = false,
  bool useMultipleDisagreementMessagePartsOnly = false,
  bool useContradictionScanMessagePartsOnly = false,
  bool useContradictionGapMessagePartsOnly = false,
  bool useMixedContradictionScanMessagePartsOnly = false,
  bool useMultipleContradictionScanMessagePartsOnly = false,
  bool useMultipleContradictionGapMessagePartsOnly = false,
  bool useFourContradictionGapMessagePartsOnly = false,
  bool useDisagreementRebuttalMessagePartsOnly = false,
  bool useMultipleDisagreementRebuttalMessagePartsOnly = false,
  bool useReviewTriageMessagePartsOnly = false,
  bool useReviewTriageOnlyMessagePartsOnly = false,
  bool useMultipleReviewTriageCandidates = false,
  bool useThinkingMessagePartsOnly = false,
  int? thinkingMessagePartCompletedAt,
  String thinkingMessagePartRoleId = 'critical',
  String? thinkingMessagePartLabel = '批判者',
  bool useSynthesisMessagePartSourceRef = false,
  bool useSynthesisMultipleEvidenceRefs = false,
  bool useNativeTimelineMessagePartsOnly = false,
  bool useLongNativeTimelineWithArtifactActions = false,
  bool useLongNativeTimelineWithReviewTriage = false,
  bool useNativeTimelineAgentTraceMessagePartsOnly = false,
  bool useRunSetupMessagePartsOnly = false,
  String directorStateLabel = 'ask-user',
  String directorStateText =
      'Which interpretation should the reader test next?',
}) {
  final human = ChatMessage.humanText('这个概念怎么理解？');
  final assistant = ChatMessage.ai('AI Seminar: 这个概念怎么理解？');
  final snapshot = includeSnapshot
      ? AiSeminarRunCardSnapshot(
          evidence: [
            const AiSeminarRunCardEvidenceSnapshot(
              title: 'Working memory',
              snippet: 'Working memory evidence.',
            ),
            if (useSnapshotMultipleEvidenceRefs)
              const AiSeminarRunCardEvidenceSnapshot(
                id: 'snapshot-evidence-2',
                title: 'Second snapshot source',
                snippet: 'Second snapshot evidence.',
              ),
            if (useSnapshotMultipleEvidenceRefs)
              const AiSeminarRunCardEvidenceSnapshot(
                id: 'snapshot-evidence-3',
                title: 'Third snapshot source',
                snippet: 'Third snapshot evidence.',
              ),
            if (useSnapshotMultipleEvidenceRefs)
              const AiSeminarRunCardEvidenceSnapshot(
                id: 'snapshot-evidence-4',
                title: 'Fourth snapshot source',
                snippet: 'Fourth snapshot evidence.',
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
    roleProfiles: roleProfiles,
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
  if (includeToolCalls) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['toolCalls'] = useSnapshotMultipleToolCalls
          ? [
              for (var i = 1; i <= 6; i++)
                {
                  'id': 'tool-call-$i',
                  'agentRunId': 'seminar-chat-history:role-critical-0:tool-$i',
                  'parentRunId': 'seminar-chat-history',
                  'toolId': 'semantic_search_current_book',
                  'query': '这个概念怎么理解？ #$i',
                  'text': 'Returned snapshot tool call $i.',
                  'resultCount': 1,
                  'roleIds': ['critical', 'supportive'],
                  'evidenceRefs': [
                    {
                      'id': 'e-tool-$i',
                      'title': 'Chapter $i',
                      'snippet': 'Tool call evidence $i.',
                    },
                  ],
                },
            ]
          : [
              {
                'id': 'tool-call-1',
                'agentRunId': 'seminar-chat-history:role-critical-0',
                'parentRunId': 'seminar-chat-history',
                'toolId': 'semantic_search_current_book',
                'query': '这个概念怎么理解？',
                'text': 'Returned 1 traceable evidence chunk.',
                'resultCount': 1,
                'roleIds': ['critical', 'supportive'],
                'evidenceRefs': [
                  {
                    'id': 'e-tool-1',
                    'title': 'Chapter 3',
                    'snippet': 'Tool call evidence.',
                  },
                ],
              },
            ];
    }
  }
  if (useRoleMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'role_turn',
          'roleId': 'critical',
          'label': '批判者',
          'text': 'This claim needs a boundary condition.',
          'evidenceRefs': [
            {
              'id': 'e1',
              'title': 'Working memory',
              'snippet': 'Working memory evidence.',
            },
            if (useRoleMultipleEvidenceRefs)
              {
                'id': 'e-role-2',
                'title': 'Second role source',
                'snippet': 'Second role evidence.',
              },
            if (useRoleMultipleEvidenceRefs)
              {
                'id': 'e-role-3',
                'title': 'Third role source',
                'snippet': 'Third role evidence.',
              },
          ],
        },
        {
          'type': 'role_turn',
          'roleId': 'supportive',
          'label': '支持者',
          'text': 'The surrounding paragraph supports it.',
        },
      ];
    }
  }
  if (useRolePartialMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'role_partial',
          'roleId': 'supportive',
          'label': '支持者',
          'text': 'Streaming role partial from message part.',
        },
      ];
    }
  }
  if (useLegacyMultipleRoleTurnMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i += 1)
          {
            'type': 'role_turn',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i.isEven ? '支持者' : '批判者',
            'text':
                i == 5 ? 'Role turn 5 should stay visible.' : 'Role turn $i.',
          },
      ];
    }
  }
  if (useLegacyMultipleRolePartialMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i += 1)
          {
            'type': 'role_partial',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i.isEven ? '支持者' : '批判者',
            'text': i == 5
                ? 'Role partial 5 should stay visible.'
                : 'Role partial $i.',
          },
      ];
    }
  }
  if (useToolCallMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      final toolCallPart = {
        'type': 'tool_call',
        'id': 'tool-call-1',
        if (useParentEvidenceToolCallMessageParts)
          'agentRunId': 'seminar-chat-history:tool:current-book'
        else
          'agentRunId': 'seminar-chat-history:role-critical-0',
        'parentRunId': 'seminar-chat-history',
        'toolId': 'semantic_search_current_book',
        if (toolCallMessagePartStatus != null)
          'status': toolCallMessagePartStatus,
        if (toolCallMessagePartStartedAt != null &&
            toolCallMessagePartStartedAt > 0)
          'startedAt': toolCallMessagePartStartedAt,
        if (toolCallMessagePartCompletedAt != null &&
            toolCallMessagePartCompletedAt > 0)
          'completedAt': toolCallMessagePartCompletedAt,
        if (toolCallMessagePartActionIds.isNotEmpty)
          'actionIds': toolCallMessagePartActionIds,
        'query': '这个概念怎么理解？',
        'text': useToolCallMultipleEvidenceRefs
            ? 'Returned 3 traceable evidence chunks.'
            : 'Returned 1 traceable evidence chunk.',
        'resultCount': useToolCallMultipleEvidenceRefs ? 3 : 1,
        'roleIds': ['critical', 'supportive'],
        'evidenceRefs': [
          {
            'id': 'e-tool-1',
            'title': 'Chapter 3',
            'snippet': 'Tool call evidence.',
          },
          if (useToolCallMultipleEvidenceRefs)
            {
              'id': 'e-tool-2',
              'title': 'Chapter 4',
              'snippet': 'Second tool call evidence.',
            },
          if (useToolCallMultipleEvidenceRefs)
            {
              'id': 'e-tool-3',
              'title': 'Chapter 5',
              'snippet': 'Third tool call evidence.',
            },
        ],
      };
      snapshotJson['messageParts'] = [
        if (keepEvidenceForToolCallMessageParts)
          {
            'type': 'evidence',
            'id': 'evidence-bundle',
            'label': '证据快照',
            'evidenceRefs': [
              {
                'id': 'e-tool-1',
                'title': 'Chapter 3',
                'snippet': 'Tool call evidence.',
              },
            ],
          },
        toolCallPart,
        if (includeLibraryFallbackToolCallMessagePart)
          {
            'type': 'tool_call',
            'id': 'tool-call-library-fallback',
            if (useParentEvidenceToolCallMessageParts)
              'agentRunId': 'seminar-chat-history:tool:library'
            else
              'agentRunId': 'seminar-chat-history:role-critical-0',
            'parentRunId': 'seminar-chat-history',
            'toolId': 'semantic_search_library',
            if (toolCallMessagePartStatus != null)
              'status': toolCallMessagePartStatus,
            'query': '这个概念怎么理解？',
            'text': 'Returned library-wide evidence.',
            'resultCount': 1,
            'roleIds': ['critical'],
            'evidenceRefs': [
              {
                'id': 'e-tool-library-1',
                'title': 'Library result',
                'snippet': 'Library fallback tool evidence.',
              },
            ],
          },
      ];
    }
  }
  if (useArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id': 'seminar-chat-history:artifact-action:knowledge-card-saved',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'completed',
          'completedAt': 1717516802000,
          'text': 'KnowledgeCard saved.',
          'actionIds': ['knowledge-card-saved'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-1',
              'title': 'Chapter 2',
              'snippet': 'Artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useSourceMissingArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id':
              'seminar-chat-history:artifact-action:knowledge-card-source-missing',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'interrupted',
          'completedAt': 1717516802000,
          'text':
              'Artifact action is missing traceable source evidence; send it to exception triage instead of saving it as a knowledge asset.',
          'actionIds': ['send-to-review'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-source-missing-1',
              'title': 'Chapter 2',
              'snippet': 'Source missing artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (usePendingInitArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id':
              'seminar-chat-history:artifact-action:knowledge-card-save-pending',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'pendingInit',
          'completedAt': 1717516802000,
          'text': 'KnowledgeCard save is being accepted.',
          'actionIds': ['save-knowledge-card'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-pending-1',
              'title': 'Chapter 2',
              'snippet': 'Pending artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useErroredArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id':
              'seminar-chat-history:artifact-action:knowledge-card-save-error',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'errored',
          'completedAt': 1717516802000,
          'text': 'KnowledgeCard save failed.',
          'actionIds': ['save-knowledge-card'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-error-1',
              'title': 'Chapter 2',
              'snippet': 'Errored artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useMissingArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id':
              'seminar-chat-history:artifact-action:knowledge-card-save-missing',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'notFound',
          'completedAt': 1717516802000,
          'text': 'KnowledgeCard save action was not found.',
          'actionIds': ['save-knowledge-card'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-missing-1',
              'title': 'Chapter 2',
              'snippet': 'Missing artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useCancelledArtifactActionsMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'artifact_actions',
          'id':
              'seminar-chat-history:artifact-action:knowledge-card-save-cancelled',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'cancelled',
          'completedAt': 1717516802000,
          'text': 'KnowledgeCard save was cancelled.',
          'actionIds': ['save-knowledge-card'],
          'evidenceRefs': [
            {
              'id': 'e-artifact-cancelled-1',
              'title': 'Chapter 2',
              'snippet': 'Cancelled artifact action evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useNativeTimelineMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'tool_call',
          'id': 'native-tool-call-1',
          'toolId': 'semantic_search_current_book',
          'query': '这个概念怎么理解？',
          'resultCount': 1,
          'roleIds': ['critical'],
          'evidenceRefs': [
            {
              'id': 'native-tool-evidence-1',
              'title': 'Chapter 3',
              'snippet': 'Native stream tool evidence.',
            },
          ],
        },
        {
          'type': 'evidence',
          'id': 'native-evidence-1',
          'label': 'Evidence snapshot',
          'evidenceRefs': [
            {
              'id': 'native-evidence-ref-1',
              'title': 'Chapter 4',
              'snippet': 'Native stream evidence bundle.',
            },
          ],
        },
        {
          'type': 'role_turn',
          'roleId': 'critical',
          'label': '批判者',
          'text': 'Native stream role turn.',
        },
        {
          'type': 'director_state',
          'id': 'native-director-1',
          'label': 'ask-user',
          'text': 'Native stream director cue.',
        },
        {
          'type': 'synthesis',
          'id': 'native-synthesis-1',
          'text': 'Native stream synthesis.',
        },
      ];
    }
  }
  if (useLongNativeTimelineWithArtifactActions) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      cardJson['status'] = 'completed';
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 12; i += 1)
          {
            'type': 'role_turn',
            'id': 'long-native-role-turn-$i',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i.isEven ? '支持者' : '批判者',
            'text': 'Long native role turn $i.',
          },
        {
          'type': 'artifact_actions',
          'id': 'long-native-artifact-actions',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'Director',
          'status': 'completed',
          'text': 'KnowledgeCard can be saved from this synthesis.',
          'actionIds': ['save-knowledge-card'],
        },
      ];
    }
  }
  if (useLongNativeTimelineWithReviewTriage) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      cardJson['status'] = 'completed';
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 12; i += 1)
          {
            'type': 'role_turn',
            'id': 'long-native-review-role-turn-$i',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i.isEven ? '支持者' : '批判者',
            'text': 'Long native role turn $i.',
          },
        {
          'type': 'review_triage',
          'id': 'long-native-review-risk',
          'label': 'risk',
          'text': 'medium',
        },
        {
          'type': 'review_triage',
          'id': 'long-native-review-action',
          'label': 'suggested-action',
          'text': 'send-to-review',
        },
      ];
    }
  }
  if (useThinkingMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'thinking',
          'id':
              'seminar-chat-history:role-$thinkingMessagePartRoleId-0:thinking:start',
          'agentRunId':
              'seminar-chat-history:role-$thinkingMessagePartRoleId-0',
          'parentRunId': 'seminar-chat-history',
          'roleId': thinkingMessagePartRoleId,
          if (thinkingMessagePartLabel != null)
            'label': thinkingMessagePartLabel,
          if (thinkingMessagePartCompletedAt != null &&
              thinkingMessagePartCompletedAt > 0)
            'completedAt': thinkingMessagePartCompletedAt,
          'text': thinkingMessagePartRoleId == 'verifier'
              ? 'Verifier is checking cited evidence.'
              : 'Critical is preparing an evidence-grounded response.',
        },
      ];
    }
  }
  if (useNativeTimelineAgentTraceMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'role_turn',
          'id': 'native-traced-role-turn-1',
          'agentRunId': 'seminar-chat-history:role-critical-0',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'critical',
          'label': '批判者',
          'text': 'Native traced role turn.',
        },
        {
          'type': 'role_partial',
          'id': 'native-traced-role-partial-1',
          'agentRunId': 'seminar-chat-history:role-supportive-1',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'supportive',
          'label': '支持者',
          'text': 'Native traced role partial.',
        },
        {
          'type': 'director_state',
          'id': 'native-traced-director-1',
          'agentRunId': 'seminar-chat-history:director',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'director',
          'label': 'ask-user',
          'text': 'Native traced director state.',
        },
        {
          'type': 'reader_turn',
          'id': 'native-traced-reader-1',
          'agentRunId': 'seminar-chat-history:role-verifier-2',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'verifier',
          'label': 'send-input',
          'text': 'Native traced reader turn.',
        },
      ];
    }
  }
  if (useRunSetupMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      cardJson['status'] = 'completed';
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'seminar_run_setup',
          'id': 'setup-seminar-chat-history',
          'label': '角色：批判者、支持者 · 证据：当前书籍 · 轮次：2',
          'text': '问题：这个概念怎么理解？',
          'roleIds': ['critical', 'supportive'],
        },
      ];
    }
  }
  if (useEvidenceMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type':
              useEvidenceBundleMessagePartType ? 'evidence_bundle' : 'evidence',
          'id': 'evidence-bundle-1',
          'label': '证据快照',
          'evidenceRefs': [
            {
              'id': 'e1',
              'title': 'Working memory',
              'snippet': 'Evidence part snippet.',
            },
            if (useEvidenceMultipleRefs)
              {
                'id': 'e2',
                'title': 'Second evidence source',
                'snippet': 'Second evidence part snippet.',
              },
            if (useEvidenceMultipleRefs)
              {
                'id': 'e3',
                'title': 'Third evidence source',
                'snippet': 'Third evidence part snippet.',
              },
            if (useEvidenceMultipleRefs)
              {
                'id': 'e4',
                'title': 'Fourth evidence source',
                'snippet': 'Fourth evidence part snippet.',
              },
          ],
        },
      ];
    }
  }
  if (useReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'user-1',
          'roleId': 'critical',
          'label': 'ask-role',
          'status': 'completed',
          'completedAt': 1717516802000,
          'text': 'Reader turn part text.',
        },
      ];
    }
  }
  if (useToolWaitReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'wait-tool-call-1',
          'agentRunId': 'seminar-chat-history:role-critical-0',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'critical',
          'label': 'wait-tool-call',
          'status': 'pending',
          'toolId': 'notes_search',
          'query': 'agency notes',
          'text': 'Waiting for tool call to finish.',
        },
      ];
    }
  }
  if (useLegacyMultipleReaderTurnMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i += 1)
          {
            'type': 'reader_turn',
            'id': 'legacy-reader-turn-$i',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i == 5 ? 'resume-agent' : 'send-input',
            'status': 'completed',
            'text': i == 5
                ? 'Reader control 5 should stay visible.'
                : 'Reader control $i.',
          },
      ];
    }
  }
  if (usePendingReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'user-pending-1',
          'roleId': 'critical',
          'label': 'send-input',
          'status': 'pending',
          'text': 'Pending reader control text.',
        },
      ];
    }
  }
  if (usePendingInitReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'user-pending-init-1',
          'roleId': 'critical',
          'label': 'send-input',
          'status': 'pendingInit',
          'text': 'Pending init reader control text.',
        },
      ];
    }
  }
  if (useCancelledReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'user-cancelled-1',
          'roleId': 'critical',
          'label': 'send-input',
          'status': cancelledReaderTurnStatus,
          'completedAt': 1717516803000,
          'text': 'Cancelled reader control text.',
        },
      ];
    }
  }
  if (usePendingWaitReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'wait-pending-1',
          'roleId': 'critical',
          'label': 'wait-agent',
          'status': 'pending',
          'text': 'Wait reader control text.',
        },
      ];
    }
  }
  if (usePendingRetryReaderTurnMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_turn',
          'id': 'retry-pending-1',
          'roleId': 'critical',
          'label': 'retry-agent-control',
          'status': 'pending',
          'text': 'Retry reader control text.',
        },
      ];
    }
  }
  if (useDirectorStateMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'director_state',
          'id': 'director-seminar-chat-history',
          'agentRunId': 'seminar-chat-history',
          'parentRunId': 'seminar-chat-history',
          'label': directorStateLabel,
          'text': directorStateText,
        },
      ];
    }
  }
  if (useLegacyMultipleDirectorStateMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 4; i += 1)
          {
            'type': 'director_state',
            'id': 'legacy-director-cue-$i',
            'label': i == 4 ? 'refresh-evidence' : 'ask-user',
            'text': i == 4
                ? 'Director cue 4 should stay visible.'
                : 'Director cue $i.',
          },
      ];
    }
  }
  if (useLegacyMultipleReaderComposerMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 3; i += 1)
          {
            'type': 'reader_composer',
            'id': 'legacy-reader-composer-$i',
            'label': 'ask-user',
            'text': i == 3
                ? 'Reader composer 3 should stay visible.'
                : 'Reader composer $i.',
            'defaultActionId': 'ask-role',
            'defaultRoleId': 'critical',
            'selectedActionId': 'ask-role',
            'selectedRoleId': i.isEven ? 'supportive' : 'critical',
            'draftText': 'Draft $i.',
            'roleIds': ['critical', 'supportive'],
            'actionIds': ['ask-role', 'refresh-evidence', 'synthesize'],
          },
      ];
    }
  }
  if (useRoleStatusMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'director_state',
          'id': 'seminar-chat-history:role-critical-0:status:running',
          'roleId': 'critical',
          'label': 'role-running',
          'text': 'Critical is running.',
          'actionIds': ['wait-agent', 'close-agent'],
          'allowedToolIds': ['semantic_search_current_book', 'notes_search'],
        },
      ];
    }
  }
  if (useRoleStatusAgentMetadataOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'director_state',
          'id': 'opaque-status-event',
          'agentRunId': 'seminar-chat-history:role-critical-0',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'critical',
          'label': 'role-running',
          'text': 'Critical is running.',
          'actionIds': ['wait-agent', 'close-agent'],
          'allowedToolIds': ['semantic_search_current_book', 'notes_search'],
        },
      ];
    }
  }
  if (useAgentStatusMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'agent_status',
          'id': 'native-agent-status-event',
          'agentRunId': 'seminar-chat-history:role-critical-0',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'critical',
          'label': agentStatusLabel,
          'text': agentStatusText,
          'actionIds': agentStatusActionIds,
          'allowedToolIds': agentStatusAllowedToolIds ??
              ['semantic_search_current_book', 'notes_search'],
        },
      ];
    }
  }
  if (useLegacyMultipleAgentStatusMessageParts) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 4; i += 1)
          {
            'type': 'agent_status',
            'id': 'legacy-agent-status-$i',
            'agentRunId': 'seminar-chat-history:role-critical-${i - 1}',
            'parentRunId': 'seminar-chat-history',
            'roleId': i.isEven ? 'supportive' : 'critical',
            'label': i == 4 ? 'role-waiting-input' : 'role-running',
            'text': i == 4
                ? 'Agent status 4 should stay visible.'
                : 'Agent status $i.',
            'actionIds': i == 4
                ? ['send-input', 'close-agent']
                : ['wait-agent', 'close-agent'],
            'allowedToolIds': ['semantic_search_current_book'],
          },
      ];
    }
  }
  if (useReaderComposerMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'reader_composer',
          'id': 'composer-seminar-chat-history',
          'label': 'ask-user',
          'text': 'Which interpretation should the reader test next?',
          'defaultActionId': 'ask-role',
          'defaultRoleId': 'critical',
          'selectedActionId': 'ask-role',
          'selectedRoleId': 'supportive',
          'draftText': 'I want the supporter to test this question.',
          'roleIds': ['critical', 'supportive'],
          'actionIds': ['ask-role', 'refresh-evidence', 'synthesize'],
        },
      ];
    }
  }
  if (useSynthesisMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['synthesisSummary'] = '';
      Map<String, Object> sourceRefJson(int index, String snippet) {
        final cfi =
            index == 0 ? 'epubcfi(/6/8)' : 'epubcfi(/6/${8 + index * 2})';
        return {
          'bookId': 7,
          'href': 'Text/ch2.xhtml',
          'cfi': cfi,
          'jumpLink':
              'paperreader://reader/open?bookId=7&cfi=${Uri.encodeComponent(cfi)}',
          'sourceTitle': 'Chapter 2',
          'locationLabel': 'Section 2.${index + 1}',
          'sourceTextSnippet': snippet,
          'sourceKind': 'current-book-rag',
        };
      }

      final synthesisEvidenceRefs = <Map<String, Object>>[
        <String, Object>{
          'id': 'e1',
          'title': 'Working memory',
          'snippet': 'Working memory evidence.',
        },
        if (useSynthesisMultipleEvidenceRefs)
          <String, Object>{
            'id': 'e2',
            'title': 'Chapter 2',
            'snippet': 'Second synthesis evidence.',
          },
        if (useSynthesisMultipleEvidenceRefs)
          <String, Object>{
            'id': 'e3',
            'title': 'Chapter 2',
            'snippet': 'Third synthesis evidence.',
          },
      ];
      if (useSynthesisMessagePartSourceRef) {
        for (var index = 0; index < synthesisEvidenceRefs.length; index += 1) {
          final item = synthesisEvidenceRefs[index];
          item['sourceRef'] = sourceRefJson(index, item['snippet']! as String);
        }
      }
      snapshotJson['messageParts'] = [
        {
          'type': 'synthesis',
          'text': 'Synthesis part summary.',
          'evidenceRefs': synthesisEvidenceRefs,
        },
      ];
    }
  }
  if (useDisagreementMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'disagreement',
          'agentRunId': 'seminar-chat-history:director:disagreement',
          'parentRunId': 'seminar-chat-history',
          'text': 'Disagreement part text.',
          'roleIds': ['critical', 'supportive'],
          'evidenceRefs': [
            {
              'id': 'e1',
              'title': 'Working memory',
              'snippet': 'Working memory evidence.',
            },
          ],
        },
      ];
    }
  }
  if (useMultipleDisagreementMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i++)
          {
            'type': 'disagreement',
            'id': 'disagreement-part-$i',
            'agentRunId': 'seminar-chat-history:director:disagreement-$i',
            'parentRunId': 'seminar-chat-history',
            'text': 'Disagreement part $i.',
            'roleIds': ['critical', 'supportive'],
          },
      ];
    }
  }
  if (useDisagreementRebuttalMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'disagreement_rebuttal',
          'id': 'turn-critical-follow-up',
          'agentRunId': 'seminar-chat-history:role-critical-1',
          'parentRunId': 'seminar-chat-history',
          'roleId': 'critical',
          'label': 'Scope remains disputed.',
          'text': 'critical follow-up response',
          'evidenceRefs': [
            {
              'id': 'e1',
              'title': 'Source passage',
              'snippet': 'The source passage.',
            },
          ],
        },
      ];
    }
  }
  if (useMultipleDisagreementRebuttalMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i++)
          {
            'type': 'disagreement_rebuttal',
            'id': 'turn-critical-follow-up-$i',
            'agentRunId': 'seminar-chat-history:role-critical-$i',
            'parentRunId': 'seminar-chat-history',
            'roleId': 'critical',
            'label': 'Disagreement target $i.',
            'text': 'Rebuttal part $i.',
          },
      ];
    }
  }
  if (useContradictionScanMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'contradiction_scan',
          'id': 'scan-disagreement-1',
          'agentRunId': 'seminar-chat-history:director:scan',
          'parentRunId': 'seminar-chat-history',
          'label': 'disagreement',
          'text': 'Scope remains disputed.',
          'roleIds': ['critical', 'supportive'],
          'evidenceRefs': [
            {
              'id': 'e-scan',
              'title': 'Scan source',
              'snippet': 'Scan evidence snippet.',
            },
          ],
        },
      ];
    }
  }
  if (useContradictionGapMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'contradiction_scan',
          'id': 'scan-gap-1',
          'label': 'evidence-gap',
          'text': 'Scope remains disputed without traceable evidence.',
          'roleIds': ['critical', 'supportive'],
        },
      ];
    }
  }
  if (useMultipleContradictionScanMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (var i = 1; i <= 5; i++)
          {
            'type': 'contradiction_scan',
            'id': 'scan-disagreement-$i',
            'agentRunId': 'seminar-chat-history:director:scan-$i',
            'parentRunId': 'seminar-chat-history',
            'label': 'disagreement',
            'text': 'Contradiction scan $i.',
            'roleIds': ['critical', 'supportive'],
          },
      ];
    }
  }
  if (useMixedContradictionScanMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'contradiction_scan',
          'id': 'scan-disagreement-1',
          'label': 'disagreement',
          'text': 'Evidence-backed scope dispute.',
          'roleIds': ['supportive'],
          'evidenceRefs': [
            {
              'id': 'e-scan-backed',
              'title': 'Scan source',
              'snippet': 'Backed scan evidence.',
            },
          ],
        },
        {
          'type': 'contradiction_scan',
          'id': 'scan-gap-1',
          'label': 'evidence-gap',
          'text': 'Missing evidence scope dispute.',
          'roleIds': ['critical'],
        },
      ];
    }
  }
  if (useMultipleContradictionGapMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'contradiction_scan',
          'id': 'scan-gap-a',
          'label': 'evidence-gap',
          'text': 'Missing evidence gap A.',
          'roleIds': ['critical'],
        },
        {
          'type': 'contradiction_scan',
          'id': 'scan-disagreement-1',
          'label': 'disagreement',
          'text': 'Evidence-backed scope dispute.',
          'roleIds': ['supportive'],
          'evidenceRefs': [
            {
              'id': 'e-scan-backed',
              'title': 'Scan source',
              'snippet': 'Backed scan evidence.',
            },
          ],
        },
        {
          'type': 'contradiction_scan',
          'id': 'scan-gap-b',
          'label': 'evidence-gap',
          'text': 'Missing evidence gap B.',
          'roleIds': ['verifier'],
        },
        {
          'type': 'contradiction_scan',
          'id': 'scan-gap-c',
          'label': 'evidence-gap',
          'text': 'Missing evidence gap C.',
          'roleIds': ['critical'],
        },
      ];
    }
  }
  if (useFourContradictionGapMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        for (final entry in const [
          ('scan-gap-a', 'Missing evidence gap A.', 'critical'),
          ('scan-gap-b', 'Missing evidence gap B.', 'verifier'),
          ('scan-gap-c', 'Missing evidence gap C.', 'critical'),
          (
            'scan-gap-d',
            'Missing evidence gap D should stay visible.',
            'supportive',
          ),
        ])
          {
            'type': 'contradiction_scan',
            'id': entry.$1,
            'label': 'evidence-gap',
            'text': entry.$2,
            'roleIds': [entry.$3],
          },
      ];
    }
  }
  if (useReviewTriageMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'synthesis',
          'text': 'Recovered review synthesis.',
          'evidenceRefs': [
            {
              'id': 'e1',
              'title': 'Working memory',
              'snippet': 'Working memory evidence.',
            },
          ],
        },
        {
          'type': 'review_triage',
          'label': 'reason',
          'text': '存在未解决分歧：1 项',
        },
        {
          'type': 'review_triage',
          'label': 'ai-suggestion',
          'text': '建议送审：未解决分歧需要人工确认。',
        },
        {
          'type': 'review_triage',
          'label': 'risk',
          'text': 'medium',
        },
        {
          'type': 'review_triage',
          'label': 'suggested-action',
          'text': 'send-to-review',
        },
        {
          'type': 'review_triage',
          'label': 'knowledge-card',
          'text': useMultipleReviewTriageCandidates
              ? 'Recovered exception card 1'
              : 'Recovered exception card',
          'evidenceRefs': [
            {
              'id': 'e-card',
              'title': 'Chapter 4',
              'snippet': 'Recovered card evidence.',
            },
          ],
        },
        if (useMultipleReviewTriageCandidates)
          for (var i = 2; i <= 4; i += 1)
            {
              'type': 'review_triage',
              'label': 'knowledge-card',
              'text': i == 4
                  ? 'Recovered exception card 4 should stay visible'
                  : 'Recovered exception card $i',
              'evidenceRefs': [
                {
                  'id': 'e-card-$i',
                  'title': 'Chapter $i',
                  'snippet': 'Recovered card evidence $i.',
                },
              ],
            },
        {
          'type': 'review_triage',
          'label': 'spaced-review',
          'text': useMultipleReviewTriageCandidates
              ? 'Recovered review question 1?'
              : 'Recovered review question?',
          'evidenceRefs': [
            {
              'id': 'e-question',
              'title': 'Chapter 1',
              'snippet': 'Recovered synthesis evidence.',
            },
          ],
        },
        if (useMultipleReviewTriageCandidates)
          for (var i = 2; i <= 4; i += 1)
            {
              'type': 'review_triage',
              'label': 'spaced-review',
              'text': i == 4
                  ? 'Recovered review question 4 should stay visible?'
                  : 'Recovered review question $i?',
              'evidenceRefs': [
                {
                  'id': 'e-question-$i',
                  'title': 'Chapter $i',
                  'snippet': 'Recovered synthesis evidence $i.',
                },
              ],
            },
      ];
    }
  }
  if (useReviewTriageOnlyMessagePartsOnly) {
    final snapshotJson = cardJson['snapshot'];
    if (snapshotJson is Map) {
      snapshotJson['evidence'] = <dynamic>[];
      snapshotJson['toolCalls'] = <dynamic>[];
      snapshotJson['roleSummaries'] = <dynamic>[];
      snapshotJson['synthesisSummary'] = '';
      snapshotJson['disagreements'] = <dynamic>[];
      snapshotJson['disagreementDetails'] = <dynamic>[];
      snapshotJson['openQuestions'] = <dynamic>[];
      snapshotJson['messageParts'] = [
        {
          'type': 'review_triage',
          'label': 'risk',
          'text': 'medium',
        },
        {
          'type': 'review_triage',
          'label': 'suggested-action',
          'text': 'send-to-review',
        },
      ];
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
  bool includeMultipleDisagreements = false,
  List<String> criticalEvidenceRefIds = const ['e1', 'e2'],
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
            AiSeminarRole.critical => criticalEvidenceRefIds,
            AiSeminarRole.supportive => const ['e3'],
            _ => const ['e4'],
          },
          whiteboardEntries: [
            if (invocation.role == AiSeminarRole.critical &&
                !includeMultipleDisagreements)
              const AiSeminarWhiteboardEntry(
                id: 'disagreement-1',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Scope remains disputed.',
                role: AiSeminarRole.critical,
                evidenceRefIds: ['e1'],
              ),
            if (invocation.role == AiSeminarRole.critical &&
                includeMultipleDisagreements)
              for (var i = 1; i <= 5; i++)
                AiSeminarWhiteboardEntry(
                  id: 'disagreement-$i',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: 'Runtime disagreement $i.',
                  role: AiSeminarRole.critical,
                  evidenceRefIds: const ['e1'],
                ),
            if (includeReviewCandidates &&
                invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'candidate-card-1',
                kind: AiSeminarWhiteboardKind.candidateCard,
                text: 'Exception card candidate',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e2', 'e3', 'e5'],
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

AiSeminarRuntimeService _seminarScopedToolCallService() {
  final currentBookRef = SourceRef(
    bookId: 7,
    href: 'Text/current.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Current-book scoped evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final libraryRef = SourceRef(
    bookId: 8,
    href: 'Text/library.xhtml',
    cfi: 'epubcfi(/6/10)',
    jumpLink: 'paperreader://reader/open?bookId=8&cfi=epubcfi%28/6/10%29',
    sourceTextSnippet: 'Library scoped evidence.',
    sourceKind: SourceRefKind.libraryRag,
  );
  final memoryRef = SourceRef(
    sourceTitle: 'Working memory',
    sourceTextSnippet: 'Memory scoped evidence.',
    sourceKind: SourceRefKind.memory,
    unavailableReason: 'local memory source can be reviewed in AI Chat',
  );
  final conceptGraphRef = SourceRef(
    sourceTitle: 'Concept graph',
    sourceTextSnippet: 'Concept graph scoped evidence.',
    sourceKind: SourceRefKind.external,
    unavailableReason: 'concept graph node source is not openable yet',
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'current-evidence',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Current-book scoped evidence.',
        sourceRef: currentBookRef,
      ),
      AiSeminarEvidence(
        id: 'library-evidence',
        scope: AiSeminarEvidenceScope.library,
        text: 'Library scoped evidence.',
        sourceRef: libraryRef,
      ),
      AiSeminarEvidence(
        id: 'memory-evidence',
        scope: AiSeminarEvidenceScope.memory,
        text: 'Memory scoped evidence.',
        sourceRef: memoryRef,
      ),
      AiSeminarEvidence(
        id: 'concept-graph-evidence',
        scope: AiSeminarEvidenceScope.conceptGraph,
        text: 'Concept graph scoped evidence.',
        sourceRef: conceptGraphRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      final evidenceId = invocation.evidenceBundle.evidence.first.id;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: [evidenceId],
        ),
      );
    },
    now: () => 1000,
  );
}

Future<void> _waitForLiveSeminarSignal(
  WidgetTester tester,
  Future<void> signal,
) async {
  await tester.runAsync(() async {
    await signal.timeout(const Duration(seconds: 2));
  });
}

Future<void> _waitForReadySeminarCardRun({
  required WidgetTester tester,
  required ProviderContainer container,
  required String sessionId,
}) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    final runtimeState = container.read(
      aiSeminarRuntimeScopedProvider(sessionId),
    );
    if (runtimeState.session?.id == sessionId &&
        runtimeState.status.isTerminal) {
      await tester.pump();
      return;
    }
  }
  final runtimeState = container.read(
    aiSeminarRuntimeScopedProvider(sessionId),
  );
  fail(
    'Seminar run $sessionId did not settle. '
    'status=${runtimeState.status.asString}',
  );
}

Future<void> _startAndWaitForReadySeminarCardRun({
  required WidgetTester tester,
  required ProviderContainer container,
  String sessionId = 'seminar-chat-history',
  int maxRounds = 1,
}) async {
  unawaited(
    container.read(aiSeminarRuntimeScopedProvider(sessionId).notifier).start(
          AiSeminarSessionContract(
            id: sessionId,
            question: '这个概念怎么理解？',
            bookId: 7,
            roles: AiSeminarRole.defaultRoles,
            maxRounds: maxRounds,
            createdAt: 1000,
          ),
        ),
  );
  await tester.pump();
  await _waitForReadySeminarCardRun(
    tester: tester,
    container: container,
    sessionId: sessionId,
  );
}

Future<void> _ensureVisibleAndTap(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _finishLiveSeminarWidgetRun({
  required WidgetTester tester,
  required ProviderContainer container,
  required String sessionId,
  required Future<void> runFuture,
}) async {
  container.read(aiSeminarRuntimeScopedProvider(sessionId).notifier).cancel();
  await tester.runAsync(() async {
    await runFuture.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  });
}

AiSeminarRuntimeService _seminarPendingEvidenceToolCallService({
  required Completer<void> evidenceFetched,
  required Completer<void> releaseRole,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live evidence before role output.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live evidence before role output.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async {
      if (!evidenceFetched.isCompleted) evidenceFetched.complete();
      return bundle;
    },
    streamRole: (invocation, _) async* {
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarBlockedEvidenceToolCallService({
  required Completer<void> evidenceStarted,
  required Completer<void> releaseEvidence,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Evidence after pending tools.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-pending',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Evidence after pending tools.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async {
      if (!evidenceStarted.isCompleted) evidenceStarted.complete();
      await releaseEvidence.future;
      return bundle;
    },
    streamRole: (invocation, _) async* {
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-pending'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarPendingLiveRoleService({
  required Completer<void> partialEmitted,
  required Completer<void> releaseRole,
  bool includeLibraryEvidence = false,
  int currentBookEvidenceCount = 1,
}) {
  SourceRef currentBookSourceRef(int index) => SourceRef(
        bookId: 7,
        href: 'Text/ch$index.xhtml',
        cfi: 'epubcfi(/6/${8 + index})',
        jumpLink:
            'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/${8 + index}%29',
        sourceTextSnippet:
            index == 1 ? 'Live role evidence.' : 'Live role evidence $index.',
        sourceKind: SourceRefKind.currentBookRag,
      );
  final currentBookEvidenceTotal =
      currentBookEvidenceCount < 1 ? 1 : currentBookEvidenceCount;
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      for (var i = 1; i <= currentBookEvidenceTotal; i++)
        AiSeminarEvidence(
          id: i == 1 ? 'e-live-role' : 'e-live-role-$i',
          scope: AiSeminarEvidenceScope.currentBook,
          text: i == 1 ? 'Live role evidence.' : 'Live role evidence $i.',
          sourceRef: currentBookSourceRef(i),
        ),
      if (includeLibraryEvidence)
        AiSeminarEvidence(
          id: 'e-live-library-role',
          scope: AiSeminarEvidenceScope.library,
          text: 'Library fallback role evidence.',
          sourceRef: SourceRef(
            bookId: 8,
            href: 'Text/library.xhtml',
            cfi: 'epubcfi(/6/12)',
            jumpLink:
                'paperreader://reader/open?bookId=8&cfi=epubcfi%28/6/12%29',
            sourceTextSnippet: 'Library fallback role evidence.',
            sourceKind: SourceRefKind.libraryRag,
          ),
        ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      yield const AiSeminarRoleStreamChunk(
        partialText: 'Partial critical response.',
      );
      if (!partialEmitted.isCompleted) partialEmitted.complete();
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarLiveAgentToolCallService({
  required Completer<void> toolEventEmitted,
  required Completer<void> releaseRole,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live role evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live-role',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live role evidence.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      await invocation.toolCallObserver?.call(const AgentToolCallEvent(
        callId: 'call-notes-live',
        toolId: 'notes_search',
        input: {'query': 'agency notes'},
        status: AgentToolCallEventStatus.completed,
        output: 'Returned 1 note match.',
        resultCount: 1,
      ));
      yield const AiSeminarRoleStreamChunk(
        partialText: 'Partial critical response.',
      );
      if (!toolEventEmitted.isCompleted) toolEventEmitted.complete();
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarLiveAgentToolCallLifecycleService({
  required Completer<void> runningToolObserved,
  required Completer<void> completedToolObserved,
  required Completer<void> releaseTool,
  required Completer<void> releaseRole,
  AgentRunGraphStore? agentRunGraphStore,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live role evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live-role',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live role evidence.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      await invocation.toolCallObserver?.call(const AgentToolCallEvent(
        callId: 'call-notes-lifecycle',
        toolId: 'notes_search',
        input: {'query': 'lifecycle notes'},
        status: AgentToolCallEventStatus.running,
      ));
      if (!runningToolObserved.isCompleted) runningToolObserved.complete();
      await releaseTool.future;
      await invocation.toolCallObserver?.call(const AgentToolCallEvent(
        callId: 'call-notes-lifecycle',
        toolId: 'notes_search',
        input: {'query': 'lifecycle notes'},
        status: AgentToolCallEventStatus.completed,
        output: 'Returned lifecycle note.',
        resultCount: 1,
      ));
      if (!completedToolObserved.isCompleted) {
        completedToolObserved.complete();
      }
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    agentRunGraphStore: agentRunGraphStore,
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarLiveAgentToolCallErrorLifecycleService({
  required Completer<void> runningToolObserved,
  required Completer<void> erroredToolObserved,
  required Completer<void> releaseTool,
  required Completer<void> releaseRole,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live role evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live-role',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live role evidence.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      await invocation.toolCallObserver?.call(const AgentToolCallEvent(
        callId: 'call-notes-error-lifecycle',
        toolId: 'notes_search',
        input: {'query': 'broken lifecycle notes'},
        status: AgentToolCallEventStatus.running,
      ));
      if (!runningToolObserved.isCompleted) runningToolObserved.complete();
      await releaseTool.future;
      await invocation.toolCallObserver?.call(const AgentToolCallEvent(
        callId: 'call-notes-error-lifecycle',
        toolId: 'notes_search',
        input: {'query': 'broken lifecycle notes'},
        status: AgentToolCallEventStatus.errored,
        error: 'notes index unavailable',
      ));
      if (!erroredToolObserved.isCompleted) {
        erroredToolObserved.complete();
      }
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarWaitingLiveRoleService({
  required Completer<void> roleStreamEntered,
  required Completer<void> releaseRole,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live role evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live-role',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live role evidence.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      if (!roleStreamEntered.isCompleted) roleStreamEntered.complete();
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarStreamedThinkingLiveRoleService({
  required Completer<void> thinkingEmitted,
  required Completer<void> releaseRole,
}) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'Live role evidence.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      AiSeminarEvidence(
        id: 'e-live-role',
        scope: AiSeminarEvidenceScope.currentBook,
        text: 'Live role evidence.',
        sourceRef: sourceRef,
      ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      yield const AiSeminarRoleStreamChunk(
        thinkingText: 'Checking note and semantic evidence.',
      );
      if (!thinkingEmitted.isCompleted) thinkingEmitted.complete();
      await releaseRole.future;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e-live-role'],
        ),
      );
    },
    now: () => 1000,
  );
}

AiSeminarRuntimeService _seminarNeedsEvidenceService() {
  return AiSeminarRuntimeService(
    fetchEvidence: (session) async => AiSeminarEvidenceBundle(
      query: session.question,
      evidence: const <AiSeminarEvidence>[],
    ),
    streamRole: (invocation, _) async* {
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
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

AiSeminarRuntimeService _seminarQuestionCaptureService(
  List<String> startedQuestions,
) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (session) async {
      startedQuestions.add(session.question);
      return AiSeminarEvidenceBundle(
        query: session.question,
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: sourceRef,
          ),
        ],
      );
    },
    streamRole: (invocation, _) async* {
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
  );
}

AiSeminarRuntimeService _seminarCardDisagreementService(
  List<String> prompts, {
  bool includeSecondDisagreement = false,
  List<String> extraDisagreements = const <String>[],
  bool uniqueFollowUpTurnIds = false,
}) {
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
  var followUpCount = 0;
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      prompts.add(invocation.prompt);
      final isFollowUp = invocation.prompt.contains('Reader intervention:');
      final followUpIndex =
          isFollowUp && uniqueFollowUpTurnIds ? ++followUpCount : null;
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: isFollowUp
              ? followUpIndex == null
                  ? 'turn-${invocation.role.asString}-follow-up'
                  : 'turn-${invocation.role.asString}-follow-up-$followUpIndex'
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
            if (!isFollowUp &&
                includeSecondDisagreement &&
                invocation.role == AiSeminarRole.supportive)
              const AiSeminarWhiteboardEntry(
                id: 'disagreement-2',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Terminology remains disputed.',
                role: AiSeminarRole.supportive,
                evidenceRefIds: ['e1'],
              ),
            if (!isFollowUp && invocation.role == AiSeminarRole.supportive)
              for (var i = 0; i < extraDisagreements.length; i += 1)
                AiSeminarWhiteboardEntry(
                  id: 'extra-disagreement-${i + 1}',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: extraDisagreements[i],
                  role: AiSeminarRole.supportive,
                  evidenceRefIds: const ['e1'],
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
  List<String> evidenceFetches, {
  bool includeDisagreementEvidenceRef = true,
}) {
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
              AiSeminarWhiteboardEntry(
                id: 'disagreement-1',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'Scope remains disputed.',
                role: AiSeminarRole.critical,
                evidenceRefIds:
                    includeDisagreementEvidenceRef ? const ['e1'] : const [],
              ),
          ],
        ),
      );
    },
    now: () => 1000,
  );
}
