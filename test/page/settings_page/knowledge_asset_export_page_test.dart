import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:papertok_reader/service/sync/sync_client_base.dart';

void main() {
  testWidgets('shows export plan and creates manifest', (tester) async {
    final service = _FakeKnowledgeAssetExportService();
    final reviewController = _FakeReviewInboxController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeAssetExportServiceProvider.overrideWithValue(service),
          reviewInboxControllerProvider.overrideWithValue(reviewController),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const KnowledgeAssetExportPage(),
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

    await tester.tap(find.text('Send conflicts to Review'));
    await tester.pump();

    expect(service.submittedConflictsToReview, true);
    expect(find.text('1 conflict sent to Review inbox'), findsOneWidget);
    expect(find.text('Review inbox'), findsOneWidget);

    await tester.tap(find.text('Create export'));
    await tester.pump();

    expect(service.createdManifest, true);
    expect(find.textContaining('knowledge_export_manifest_v1.json'), findsOne);
    expect(find.textContaining('knowledge_export_v1.md'), findsOne);
    expect(
      find.textContaining('knowledge_export_study_report.html'),
      findsOne,
    );
    expect(find.textContaining('knowledge_export_anki.tsv'), findsOne);
    expect(find.textContaining('knowledge_sync_bundle_v1.json'), findsOne);

    await tester.tap(find.text('Preview remote sync'));
    await tester.pump();

    expect(service.previewedRemoteSync, true);
    expect(find.text('Remote sync preview'), findsOneWidget);
    expect(find.text('2 remote'), findsOneWidget);
    expect(find.text('1 incoming'), findsOneWidget);
    expect(find.text('1 remote conflict'), findsOneWidget);

    await tester.tap(find.text('Send remote conflicts to Review'));
    await tester.pump();

    expect(service.submittedRemoteConflictsToReview, true);
    await tester.scrollUntilVisible(
      find.text('1 remote conflict sent to Review inbox'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 remote conflict sent to Review inbox'), findsOneWidget);

    await tester.tap(find.text('Review inbox').last);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewInboxPage), findsOneWidget);
    expect(reviewController.listCalled, true);
  });

  testWidgets('remote preview failure keeps export plan visible',
      (tester) async {
    final service = _FakeKnowledgeAssetExportService();
    final reviewController = _FakeReviewInboxController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeAssetExportServiceProvider.overrideWithValue(service),
          reviewInboxControllerProvider.overrideWithValue(reviewController),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const KnowledgeAssetExportPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('1 included'), findsWidgets);

    await tester.tap(find.text('Preview remote sync'));
    await tester.pump();
    expect(find.text('Remote sync preview'), findsOneWidget);

    service.failRemotePreview = true;
    await tester.tap(find.text('Preview remote sync'));
    await tester.pump();

    expect(find.text('1 included'), findsWidgets);
    expect(find.text('Remote sync preview'), findsNothing);
    expect(find.textContaining('remote unavailable'), findsOneWidget);
  });
}

class _FakeReviewInboxController extends ReviewInboxController {
  bool listCalled = false;

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    listCalled = true;
    return const <ReviewItem>[];
  }
}

class _FakeKnowledgeAssetExportService extends KnowledgeAssetExportService {
  _FakeKnowledgeAssetExportService()
      : super(rootDir: Directory.systemTemp.createTempSync());

  bool createdManifest = false;
  bool submittedConflictsToReview = false;
  bool previewedRemoteSync = false;
  bool submittedRemoteConflictsToReview = false;
  bool failRemotePreview = false;

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
    createdManifest = true;
    return KnowledgeAssetExportManifestResult(
      file: File('/tmp/knowledge_export_manifest_v1.json'),
      markdownFile: File('/tmp/knowledge_export_v1.md'),
      htmlReportFile: File('/tmp/knowledge_export_study_report.html'),
      ankiFile: File('/tmp/knowledge_export_anki.tsv'),
      syncBundleFile: File('/tmp/knowledge_sync_bundle_v1.json'),
      snapshot: await buildSnapshot(),
    );
  }

  @override
  Future<KnowledgeAssetConflictReviewResult> submitConflictsToReview() async {
    submittedConflictsToReview = true;
    return KnowledgeAssetConflictReviewResult(
      submittedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
    );
  }

  @override
  Future<KnowledgeRemoteSyncPreview> previewRemoteSync({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    previewedRemoteSync = true;
    return _remotePreview(await buildSnapshot());
  }

  @override
  Future<KnowledgeAssetConflictReviewResult> submitRemoteConflictsToReview({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    submittedRemoteConflictsToReview = true;
    return KnowledgeAssetConflictReviewResult(
      submittedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
      remotePreview: _remotePreview(await buildSnapshot()),
    );
  }

  KnowledgeRemoteSyncPreview _remotePreview(
    KnowledgeAssetExportSnapshot snapshot,
  ) {
    const remoteIncoming = KnowledgeSyncEnvelope(
      id: 'remote-incoming',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      payload: {'title': 'Remote incoming'},
    );
    const remoteConflict = KnowledgeSyncEnvelope(
      id: 'remote-conflict',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      payload: {'title': 'Remote conflict'},
    );
    return KnowledgeRemoteSyncPreview(
      local: snapshot.included,
      remote: const [remoteIncoming, remoteConflict],
      incoming: const [remoteIncoming],
      outgoing: const <KnowledgeSyncEnvelope>[],
      conflicts: const [remoteConflict],
      remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
    );
  }
}
