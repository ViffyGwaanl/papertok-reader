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
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AI settings navigation widgets compile', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(const AISettings(), isA<AISettings>());
    expect(const AiSeminarRuntimePage(), isA<AiSeminarRuntimePage>());
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
