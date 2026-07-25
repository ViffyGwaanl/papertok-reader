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
import 'package:ai_provider_kit/ai_provider_kit.dart';
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
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _aiChatStreamSource() =>
    File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'AiChatStream no longer carries an inline Seminar panel render path',
    () {
      final source = _aiChatStreamSource();

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
      final source = _aiChatStreamSource();

      expect(source, isNot(contains("if (skill.id == 'seminar_mode')")));
    },
  );

  test(
    'Seminar chat run card does not jump to global Seminar settings',
    () {
      final source = _aiChatStreamSource();

      expect(source, isNot(contains('AiSeminarConfigPage')));
      expect(source, isNot(contains('ai_seminar_config.dart')));
    },
  );

  test(
    'AI Chat skill localization does not expose the native Seminar marker',
    () {
      final source = _aiChatStreamSource();

      expect(source, isNot(contains('aiSkillSeminarModeName')));
      expect(source, isNot(contains('aiSkillSeminarModeDesc')));
    },
  );

  test(
    'Seminar wait failure copy uses native wait wording',
    () {
      final source = _aiChatStreamSource();

      expect(source, contains("zh: '未能等待角色'"));
      expect(source, contains("en: 'Could not wait for role'"));
      expect(source, contains("zh: '未能等待证据检索'"));
      expect(source, contains("en: 'Could not wait for evidence retrieval'"));
      expect(source, isNot(contains("zh: '未能刷新角色'")));
      expect(source, isNot(contains("en: 'Could not refresh role'")));
      expect(source, isNot(contains("zh: '未能刷新工具调用'")));
      expect(source, isNot(contains("en: 'Could not refresh tool call'")));
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
      await tester.tap(find.text('Native stream role turn.').last);
      await tester.pump();
      expect(find.text('收起'), findsOneWidget);

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
      final evidenceRefs = card?.snapshot?.messageParts
          .where((part) => part.type == 'evidence')
          .expand((part) => part.evidenceRefs)
          .toList(growable: false);
      expect(
        evidenceRefs?.map((item) => item.id),
        contains('e1'),
      );
      expect(
        evidenceRefs?.map((item) => item.snippet),
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
      expect(
        card?.snapshot?.messageParts
            .where((part) =>
                part.agentRunId == '$seminarSessionId:role-critical-0' &&
                part.toolId == 'notes_search')
            .toList(growable: false),
        isEmpty,
      );
      final synthesisPart = card?.snapshot?.messageParts
          .where((part) => part.type == 'synthesis')
          .firstOrNull;
      expect(synthesisPart?.text, 'synthesizer response');
      expect(synthesisPart?.agentRunId, seminarSessionId);
      expect(synthesisPart?.parentRunId, seminarSessionId);
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

      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
      expect(find.text('研讨流'), findsOneWidget);
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
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
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
      expect(find.text('Working memory evidence.'), findsAtLeastNWidgets(1));
      expect(find.text('分歧视图'), findsNothing);
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
            home: const Scaffold(body: AiChatStream()),
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
      expect(find.text('查看知识卡'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('查看知识卡'));
      await tester.pumpAndSettle();

      expect(find.text('知识卡详情'), findsOneWidget);
      expect(find.text('AI Seminar synthesis'), findsOneWidget);
      expect(find.text('synthesizer response'), findsWidgets);
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
            home: const Scaffold(body: AiChatStream()),
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
      expect(find.text('查看知识卡'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('查看知识卡'));
      await tester.pumpAndSettle();

      expect(find.text('知识卡详情'), findsOneWidget);
      expect(find.text('读者改过的标题'), findsOneWidget);
      expect(find.text('读者改过的解释'), findsOneWidget);
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
