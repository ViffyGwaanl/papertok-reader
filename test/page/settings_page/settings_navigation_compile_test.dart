import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/page/home_page/settings_page.dart';
import 'package:papertok_reader/page/settings_page/ai.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AI settings navigation widgets compile', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(const AISettings(), isA<AISettings>());
    expect(const AiSeminarRuntimePage(), isA<AiSeminarRuntimePage>());
    expect(const CustomSkillsPage(), isA<CustomSkillsPage>());
    expect(const ReviewInboxPage(), isA<ReviewInboxPage>());
    expect(const ConceptGraphExplorerPage(), isA<ConceptGraphExplorerPage>());
    expect(const SpacedReviewPage(), isA<SpacedReviewPage>());
    expect(
      const KnowledgeAssetExportPage(),
      isA<KnowledgeAssetExportPage>(),
    );
  });

  testWidgets('AI settings opens structured Seminar runtime entry',
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
    await tester.ensureVisible(find.text('Seminar Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seminar Mode'));
    await tester.pumpAndSettle();

    expect(find.byType(AiSeminarRuntimePage), findsOneWidget);
    expect(find.text('Start Seminar'), findsOneWidget);
  });

  testWidgets('AI settings opens custom skills entry', (tester) async {
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

  testWidgets('AI settings opens knowledge sync export entry', (tester) async {
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
          home: AISettings(),
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

  testWidgets('AI settings opens concept graph entry', (tester) async {
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
          home: AISettings(),
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
}

Future<void> _pumpNavigationFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
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
