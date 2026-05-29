import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';

void main() {
  testWidgets('shows export plan and creates manifest', (tester) async {
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
          home: KnowledgeAssetExportPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Knowledge sync/export'), findsWidgets);
    expect(find.text('1 included'), findsWidgets);
    expect(find.text('1 excluded'), findsWidgets);
    expect(find.text('1 conflict'), findsOneWidget);

    await tester.tap(find.text('Create export'));
    await tester.pump();

    expect(service.createdManifest, true);
    expect(find.textContaining('knowledge_export_manifest_v1.json'), findsOne);
    expect(find.textContaining('knowledge_export_v1.md'), findsOne);
  });
}

class _FakeKnowledgeAssetExportService extends KnowledgeAssetExportService {
  _FakeKnowledgeAssetExportService()
      : super(rootDir: Directory.systemTemp.createTempSync());

  bool createdManifest = false;

  @override
  Future<KnowledgeAssetExportSnapshot> buildSnapshot({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    const included = KnowledgeSyncEnvelope(
      id: 'card1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {'title': 'Card'},
    );
    const conflict = KnowledgeSyncEnvelope(
      id: 'conflict1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      payload: {'title': 'Conflict'},
    );
    return KnowledgeAssetExportSnapshot(
      manifest: const KnowledgeExportManifest(
        id: 'export1',
        createdAt: 100,
        formats: [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: ['card1'],
      ),
      included: const [included],
      excluded: const [conflict],
      excludedReasons: const {
        'conflict1': 'pending-conflict-review',
      },
    );
  }

  @override
  Future<KnowledgeAssetExportManifestResult> writeManifest({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    createdManifest = true;
    return KnowledgeAssetExportManifestResult(
      file: File('/tmp/knowledge_export_manifest_v1.json'),
      markdownFile: File('/tmp/knowledge_export_v1.md'),
      snapshot: await buildSnapshot(),
    );
  }
}
