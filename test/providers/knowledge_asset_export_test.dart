import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';

void main() {
  test('refresh exposes included excluded and conflict counts', () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.snapshot.value!.includedCount, 1);
    expect(state.snapshot.value!.excludedCount, 1);
    expect(state.snapshot.value!.conflictCount, 1);
  });

  test('createManifest exposes manifest markdown html and anki paths',
      () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .createManifest();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.lastManifestPath, '/tmp/knowledge_export_manifest_v1.json');
    expect(state.lastMarkdownPath, '/tmp/knowledge_export_v1.md');
    expect(
      state.lastHtmlReportPath,
      '/tmp/knowledge_export_study_report.html',
    );
    expect(state.lastAnkiPath, '/tmp/knowledge_export_anki.tsv');
    expect(state.snapshot.value!.includedCount, 1);
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
          KnowledgeExportFormat.html,
          KnowledgeExportFormat.anki,
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
    return KnowledgeAssetExportManifestResult(
      file: File('/tmp/knowledge_export_manifest_v1.json'),
      markdownFile: File('/tmp/knowledge_export_v1.md'),
      htmlReportFile: File('/tmp/knowledge_export_study_report.html'),
      ankiFile: File('/tmp/knowledge_export_anki.tsv'),
      snapshot: await buildSnapshot(),
    );
  }
}
