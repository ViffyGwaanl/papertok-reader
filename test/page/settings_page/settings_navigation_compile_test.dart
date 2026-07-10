import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/page/home_page/settings_page.dart';
import 'package:papertok_reader/page/settings_page/ai.dart';
import 'package:papertok_reader/page/settings_page/ai_library_index_page.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:papertok_reader/page/settings_page/home_navigation.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AI settings navigation widgets compile', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(const AISettings(), isA<AISettings>());
    expect(const AiLibraryIndexPage(), isA<AiLibraryIndexPage>());
    expect(const AiSeminarConfigPage(), isA<AiSeminarConfigPage>());
    expect(const CustomSkillsPage(), isA<CustomSkillsPage>());
    expect(const ReviewInboxPage(), isA<ReviewInboxPage>());
    expect(const ConceptGraphExplorerPage(), isA<ConceptGraphExplorerPage>());
    expect(const SpacedReviewPage(), isA<SpacedReviewPage>());
    expect(
      const KnowledgeAssetExportPage(),
      isA<KnowledgeAssetExportPage>(),
    );
  });

  testWidgets('AI settings removes standalone Seminar runtime entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Seminar Mode'),
      findsNothing,
      reason:
          'Seminar must run from native AI Chat cards, not a standalone page.',
    );
    expect(
      find.text('Seminar settings'),
      findsNothing,
      reason: 'E4 batch 3 stowed the Seminar config entry under '
          'Developer Options.',
    );
    expect(
      File('lib/page/settings_page/ai_seminar_runtime.dart').existsSync(),
      isFalse,
      reason:
          'The old standalone Seminar page should not remain as a compatibility surface.',
    );
  });

  test('AI Seminar activation plan does not gate on the deleted runtime page',
      () {
    final activationPlan = File(
      'docs/ai/future_agentic_upgrade/04_user_facing_activation_plan_zh.md',
    ).readAsStringSync();
    expect(
      activationPlan,
      isNot(contains(
          'test/page/settings_page/ai_seminar_runtime_page_test.dart')),
      reason:
          'P1 verification must not keep a deleted standalone page test as a gate.',
    );
    expect(
      activationPlan,
      isNot(contains('AiSeminarRuntimePage')),
      reason:
          'The user-facing activation plan should not keep deleted page class names in the live entry documentation.',
    );
    expect(
      activationPlan,
      isNot(contains('AiSeminarRuntimePanel')),
      reason:
          'The user-facing activation plan should describe native AI Chat cards, not the old panel class.',
    );

    final ufaSeminarRows = activationPlan
        .split('\n')
        .where((line) => line.startsWith('| UFA-C02-'))
        .join('\n');
    expect(
      ufaSeminarRows,
      isNot(contains('AiSeminarRuntimePage')),
      reason:
          'UFA-C02 rows should name native AI Chat card/runtime artifacts, not the deleted standalone page.',
    );
    expect(
      ufaSeminarRows,
      isNot(contains('AiSeminarRuntimePanel')),
      reason:
          'User-in-the-loop Seminar must be accepted through native AI Chat UI, not the old panel.',
    );
  });

  test('AI Seminar settings copy points default overrides back to AI Chat', () {
    final localizedCopies = {
      'en': File('lib/l10n/app_en.arb').readAsStringSync(),
      'zh': File('lib/l10n/app_zh.arb').readAsStringSync(),
      'zh-CN': File('lib/l10n/app_zh-CN.arb').readAsStringSync(),
    };

    for (final entry in localizedCopies.entries) {
      expect(
        entry.value,
        isNot(contains('run page')),
        reason:
            'Seminar settings should not imply a standalone runtime page in ${entry.key}.',
      );
      expect(
        entry.value,
        isNot(contains('运行页')),
        reason:
            'Seminar settings should send per-run overrides to native AI Chat in ${entry.key}.',
      );
    }
  });

  test('v7 goal index uses checkpoint details for Seminar resume entry', () {
    final goalIndex = File(
      'docs/ai/future_agentic_upgrade/06_v7_goal_and_priority_plan_index_zh.md',
    ).readAsStringSync();

    expect(
      goalIndex,
      contains('`断点详情`'),
      reason:
          'The authoritative goal index should reflect the current native AI Chat checkpoint entry label.',
    );
    expect(
      goalIndex,
      isNot(contains('同 session 本机 running checkpoint 的 `恢复详情` 已')),
      reason:
          'Current progress in the goal index must not describe the checkpoint details entry with the old resume-details label.',
    );
    expect(
      goalIndex,
      isNot(contains('用户点 `恢复详情`')),
      reason:
          'The goal index is the entry point for future agents, so it must not instruct the old user-facing checkpoint action.',
    );
  });

  test('AI Seminar planning docs do not keep prompt-style fallback wording',
      () {
    final docs = [
      File(
        'docs/ai/future_agentic_upgrade/epics/E01_openmaic_multi_role_discussion_zh.md',
      ).readAsStringSync(),
      File(
        'docs/ai/future_agentic_upgrade/05_openmaic_discussion_reference_zh.md',
      ).readAsStringSync(),
    ].join('\n');

    for (final phrase in [
      '`seminar_mode` 只是普通 AI Chat 多视角 prompt 风格',
      '`seminar_mode` 作为普通多视角回复风格保留降级用途',
      '`seminar_mode` 仍是普通 AI Chat prompt 风格',
      '旧 skill 保留降级用途',
      '降级回 prompt-only `seminar_mode`',
    ]) {
      expect(
        docs,
        isNot(contains(phrase)),
        reason:
            'Native AI Seminar planning docs must not describe Seminar as a reusable prompt style or fallback skill.',
      );
    }
  });

  test('AI settings skill localization does not expose native Seminar marker',
      () {
    final source = File('lib/page/settings_page/ai.dart').readAsStringSync();

    expect(source, isNot(contains('aiSkillSeminarModeName')));
    expect(source, isNot(contains('aiSkillSeminarModeDesc')));
  });

  test('AI l10n resources do not keep native Seminar as skill copy', () {
    final files = <File>[
      ...Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb')),
      ...Directory('lib/l10n/generated')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('aiSkillSeminarModeName')),
        reason: '${file.path} must not keep Seminar as a normal skill name.',
      );
      expect(
        source,
        isNot(contains('aiSkillSeminarModeDesc')),
        reason:
            '${file.path} must not keep Seminar as a normal skill description.',
      );
    }
  });

  testWidgets('Developer options opens Seminar settings entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DeveloperOptionsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Seminar settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seminar settings'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(AiSeminarConfigPage), findsOneWidget);
    expect(find.text('How Seminar runs'), findsOneWidget);
    expect(
      find.textContaining('role agents orchestrated by generated prompts'),
      findsOneWidget,
    );
  });

  test('Seminar role tools allow local graph tools as read-only native tools',
      () {
    for (final toolId in const ['memory_search', 'concept_graph_search']) {
      final readingRule = AiToolPermissionMatrix.defaultMatrix.ruleFor(toolId);
      expect(readingRule, isNotNull, reason: '$toolId reading rule');
      expect(readingRule!.readOnly, isTrue);
      expect(readingRule.requiresApproval, isFalse);
      expect(readingRule.allowsExternalNetwork, isFalse);
      expect(readingRule.allows(AiAgentScene.seminar), isTrue);

      final libraryRule =
          AiToolPermissionMatrix.seminarLibraryFallbackMatrix.ruleFor(toolId);
      expect(libraryRule, isNotNull, reason: '$toolId fallback rule');
      expect(libraryRule!.readOnly, isTrue);
      expect(libraryRule.requiresApproval, isFalse);
      expect(libraryRule.allowsExternalNetwork, isFalse);
      expect(libraryRule.allows(AiAgentScene.seminar), isTrue);
    }
  });

  testWidgets('Seminar settings exposes local graph search as a role tool',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().aiSeminarRoleProfiles = [
      AiSeminarRoleProfile(
        role: AiSeminarRole.critical,
        allowedToolIds: ['semantic_search_current_book'],
      ),
    ];

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarConfigPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final memoryTool = find.byKey(
      const ValueKey('seminar-role-critical-tool-memory_search'),
    );
    await tester.ensureVisible(memoryTool);
    await tester.pumpAndSettle();

    expect(memoryTool, findsOneWidget);
    expect(find.text('Memory search'), findsOneWidget);
    expect(find.text('memory_search'), findsNothing);

    final checkbox = tester.widget<CheckboxListTile>(memoryTool);
    expect(checkbox.value, isFalse);
    checkbox.onChanged?.call(true);
    await tester.pumpAndSettle();

    expect(
      Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.allowedToolIds,
      contains('memory_search'),
    );

    final graphTool = find.byKey(
      const ValueKey('seminar-role-critical-tool-concept_graph_search'),
    );
    await tester.ensureVisible(graphTool);
    await tester.pumpAndSettle();

    expect(graphTool, findsOneWidget);
    expect(find.text('Concept graph search'), findsOneWidget);
    expect(find.text('concept_graph_search'), findsNothing);

    final graphCheckbox = tester.widget<CheckboxListTile>(graphTool);
    expect(graphCheckbox.value, isFalse);
    graphCheckbox.onChanged?.call(true);
    await tester.pumpAndSettle();

    expect(
      Prefs().aiSeminarRoleProfileFor(AiSeminarRole.critical)?.allowedToolIds,
      contains('concept_graph_search'),
    );
  });

  testWidgets('Developer options opens custom skills entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DeveloperOptionsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom skills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom skills'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(CustomSkillsPage), findsOneWidget);
    expect(find.text('Import skill'), findsOneWidget);
  });

  testWidgets('AI settings shows active custom skill name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "slow_reader",
  "name": "Slow Reader",
  "description": "Explain locally.",
  "systemPromptAppend": "Move slowly and cite current-book evidence.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": true
}
''');
    Prefs().activeAiSkillId = 'slow_reader';

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Active Skill'));
    await tester.pumpAndSettle();

    expect(find.text('Slow Reader'), findsOneWidget);
  });

  testWidgets('AI settings active skill picker excludes native Seminar mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'activeAiSkillId': 'seminar_mode',
    });
    await Prefs().initPrefs();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Active Skill'));
    await tester.pumpAndSettle();

    expect(
      find.text('Seminar Mode'),
      findsNothing,
      reason:
          'Seminar should be configured from its native AI Chat entry, not selected as a normal prompt skill.',
    );
    expect(find.text('None'), findsWidgets);

    await tester.tap(find.text('Active Skill'));
    await tester.pumpAndSettle();

    expect(find.text('Seminar Mode'), findsNothing);
  });

  testWidgets('AI settings opens Review Inbox entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewInboxControllerProvider.overrideWithValue(
            _EmptyReviewInboxController(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review inbox'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(ReviewInboxPage), findsOneWidget);
    expect(find.text('Nothing waiting for review'), findsOneWidget);
  });

  testWidgets('home Settings top AI section opens Review Inbox directly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewInboxControllerProvider.overrideWithValue(
            _EmptyReviewInboxController(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review inbox'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(ReviewInboxPage), findsOneWidget);
    expect(find.text('Nothing waiting for review'), findsOneWidget);
  });

  testWidgets('AI settings picker activates enabled custom skill only',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "local_terms",
  "name": "Local Terms",
  "description": "Explain local concepts.",
  "systemPromptAppend": "Prefer local term definitions.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": true
}
''');
    await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "disabled_terms",
  "name": "Disabled Terms",
  "description": "Should stay hidden.",
  "systemPromptAppend": "This disabled skill must not be selectable.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": false
}
''');

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Active Skill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active Skill'));
    await tester.pumpAndSettle();

    expect(find.text('Local Terms'), findsOneWidget);
    expect(find.text('Disabled Terms'), findsNothing);

    await tester.tap(find.text('Local Terms'));
    await tester.pumpAndSettle();

    expect(Prefs().activeAiSkillId, 'local_terms');
    expect(find.text('Local Terms'), findsOneWidget);
  });

  testWidgets('Developer options opens knowledge sync export entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final service = _FakeKnowledgeAssetExportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeAssetExportServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DeveloperOptionsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Knowledge sync/export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Knowledge sync/export'));
    await tester.pumpAndSettle();

    expect(find.byType(KnowledgeAssetExportPage), findsOneWidget);
    expect(find.text('No confirmed knowledge assets yet'), findsOneWidget);
  });

  testWidgets('Developer options opens concept graph entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final tempRoot = Directory.systemTemp.createTempSync();
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(
            ConceptGraphStore(rootDir: tempRoot),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DeveloperOptionsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Concept graph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concept graph'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(ConceptGraphExplorerPage), findsOneWidget);
    expect(
      find.text(
        'Explore confirmed and draft concept relationships with evidence back to the book.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AI settings opens spaced review entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final tempRoot = Directory.systemTemp.createTempSync();
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spacedReviewStoreProvider.overrideWithValue(
            SpacedReviewStore(rootDir: tempRoot),
          ),
          spacedReviewKnowledgeCardStoreProvider.overrideWithValue(
            KnowledgeCardStore(rootDir: tempRoot),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AISettings(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Spaced review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spaced review'));
    await _pumpNavigationFrames(tester);

    expect(find.byType(SpacedReviewPage), findsOneWidget);
    expect(
      find.text(
        'Review applied knowledge cards with source links back to the original text.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('home navigation exposes Memory tab toggle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: HomeNavigationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Memory'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });
}

Future<void> _pumpNavigationFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

class _EmptyReviewInboxController extends ReviewInboxController {
  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return const <ReviewItem>[];
  }
}

class _FakeKnowledgeAssetExportService extends KnowledgeAssetExportService {
  _FakeKnowledgeAssetExportService()
      : super(rootDir: Directory.systemTemp.createTempSync());

  @override
  Future<KnowledgeAssetExportSnapshot> buildSnapshot({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    return const KnowledgeAssetExportSnapshot(
      manifest: KnowledgeExportManifest(
        id: 'empty-export',
        createdAt: 100,
        formats: [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
      ),
      included: <KnowledgeSyncEnvelope>[],
      excluded: <KnowledgeSyncEnvelope>[],
      excludedReasons: <String, String>{},
    );
  }
}
