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
    expect(find.text('Remote sync status: Not previewed'), findsOneWidget);
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
    expect(find.text('Remote sync status: Review required'), findsOneWidget);
    expect(
      find.textContaining('Send incoming items or conflicts to Review'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Remote sync preview'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Remote sync preview'), findsOneWidget);
    expect(find.text('3 remote'), findsOneWidget);
    expect(find.text('2 incoming'), findsOneWidget);
    expect(find.text('1 remote conflict'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Send remote incoming to Review'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send remote incoming to Review'));
    await tester.pump();

    expect(service.submittedRemoteIncomingToReview, true);
    await tester.scrollUntilVisible(
      find.text('1 remote incoming sent to Review inbox'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 remote incoming sent to Review inbox'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Send remote review history to Review'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send remote review history to Review'));
    await tester.pump();

    expect(service.submittedRemoteReviewHistoryToReview, true);
    await tester.scrollUntilVisible(
      find.text('1 remote review history sent to Review inbox'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1 remote review history sent to Review inbox'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Upload sync bundle'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload sync bundle'));
    await tester.pump();

    expect(service.uploadedRemoteSyncBundle, true);
    await tester.scrollUntilVisible(
      find.text('Remote sync status: Uploaded'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Remote sync status: Uploaded'), findsOneWidget);
    expect(
      find.textContaining('Latest protected upload completed'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Uploaded sync bundle'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploaded sync bundle'), findsOneWidget);
    expect(
      find.textContaining(
        'Uploaded sync bundle: paper_reader/.knowledge',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Stage safe remote card conflicts to Review'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage safe remote card conflicts to Review'));
    await tester.pump();

    expect(service.stagedRemoteKnowledgeCardConflictsToReview, true);
    await tester.scrollUntilVisible(
      find.text('1 safe remote card conflict staged for Review inbox'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1 safe remote card conflict staged for Review inbox'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Send remote conflicts to Review'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
    expect(find.text('Remote sync status: Failed'), findsOneWidget);
    expect(
      find.textContaining('Last remote operation failed'),
      findsOneWidget,
    );
    expect(find.text('Remote sync preview'), findsNothing);
    expect(find.textContaining('remote unavailable'), findsOneWidget);
  });

  testWidgets('run safe remote sync batches blockers into Review',
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

    await tester.tap(find.text('Run safe remote sync'));
    await tester.pumpAndSettle();

    expect(service.previewedRemoteSync, true);
    expect(service.stagedRemoteKnowledgeCardConflictsToReview, true);
    expect(service.submittedRemoteConflictsToReview, true);
    expect(service.submittedRemoteIncomingToReview, true);
    expect(service.submittedRemoteReviewHistoryToReview, true);
    expect(service.uploadedRemoteSyncBundle, false);
    expect(find.text('Remote sync status: Review required'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('1 remote incoming sent to Review inbox'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 remote incoming sent to Review inbox'), findsOneWidget);
    expect(find.text('1 remote conflict sent to Review inbox'), findsOneWidget);
    expect(
      find.text('1 safe remote card conflict staged for Review inbox'),
      findsOneWidget,
    );
    expect(
      find.text('1 remote review history sent to Review inbox'),
      findsOneWidget,
    );
  });

  testWidgets('remote writeback rollback status is visible', (tester) async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithRollback = true;
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

    await tester.tap(find.text('Upload sync bundle'));
    await tester.pump();

    expect(find.text('Remote sync status: Failed'), findsOneWidget);
    expect(find.textContaining('remote writeback failed'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Rollback snapshot: /tmp/remote-rollback.json'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Rollback snapshot: /tmp/remote-rollback.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('the previous remote bundle was restored'),
      findsOneWidget,
    );
  });

  testWidgets('remote precondition failure asks user to preview again',
      (tester) async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithPrecondition = true;
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

    await tester.tap(find.text('Upload sync bundle'));
    await tester.pump();

    expect(
      find.text('Remote sync status: Re-preview required'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Preview remote sync again before uploading'),
      findsOneWidget,
    );
  });

  testWidgets('unsupported conditional writes show guard unavailable',
      (tester) async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithoutConditionalGuard = true;
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

    await tester.tap(find.text('Upload sync bundle'));
    await tester.pump();

    expect(
      find.text('Remote sync status: Concurrency guard unavailable'),
      findsOneWidget,
    );
    expect(
      find.textContaining('did not expose ETag/CAS protection'),
      findsOneWidget,
    );
  });

  testWidgets('remote preview without blockers shows ready-to-upload status',
      (tester) async {
    final service = _FakeKnowledgeAssetExportService()
      ..remotePreviewHasBlockers = false;
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

    await tester.tap(find.text('Preview remote sync'));
    await tester.pump();

    expect(find.text('Remote sync status: Ready to upload'), findsOneWidget);
    expect(
      find.textContaining('No remote incoming items or conflicts were found'),
      findsOneWidget,
    );
    expect(find.text('0 incoming'), findsOneWidget);
    expect(find.text('0 remote conflict'), findsOneWidget);
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
  bool stagedRemoteKnowledgeCardConflictsToReview = false;
  bool submittedRemoteIncomingToReview = false;
  bool submittedRemoteReviewHistoryToReview = false;
  bool uploadedRemoteSyncBundle = false;
  bool failRemotePreview = false;
  bool failRemoteWritebackWithRollback = false;
  bool failRemoteWritebackWithPrecondition = false;
  bool failRemoteWritebackWithoutConditionalGuard = false;
  bool remotePreviewHasBlockers = true;

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

  @override
  Future<KnowledgeRemoteConflictStageResult>
      stageRemoteKnowledgeCardConflictsToReview({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    stagedRemoteKnowledgeCardConflictsToReview = true;
    return KnowledgeRemoteConflictStageResult(
      stagedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
      remotePreview: _remotePreview(await buildSnapshot()),
    );
  }

  @override
  Future<KnowledgeRemoteIncomingReviewResult> submitRemoteIncomingToReview({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    submittedRemoteIncomingToReview = true;
    return KnowledgeRemoteIncomingReviewResult(
      submittedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
      remotePreview: _remotePreview(await buildSnapshot()),
    );
  }

  @override
  Future<KnowledgeRemoteReviewHistoryReviewResult>
      submitRemoteReviewHistoryToReview({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    submittedRemoteReviewHistoryToReview = true;
    return KnowledgeRemoteReviewHistoryReviewResult(
      submittedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
      remotePreview: _remotePreview(await buildSnapshot()),
    );
  }

  @override
  Future<KnowledgeRemoteSyncUploadResult> uploadRemoteSyncBundle({
    SyncClientBase? client,
    String remotePath = KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
  }) async {
    if (failRemotePreview) {
      throw StateError('remote unavailable');
    }
    if (failRemoteWritebackWithRollback) {
      throw const KnowledgeRemoteWritebackException(
        message: 'remote writeback failed',
        remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
        rollbackSnapshotPath: '/tmp/remote-rollback.json',
        rollbackRestored: true,
      );
    }
    if (failRemoteWritebackWithPrecondition) {
      throw const KnowledgeRemoteWritebackException(
        message:
            'Remote sync writeback blocked because the remote bundle changed after preview.',
        remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
        remotePreconditionFailed: true,
      );
    }
    if (failRemoteWritebackWithoutConditionalGuard) {
      throw const KnowledgeRemoteWritebackException(
        message: 'Remote sync writeback requires ETag/CAS support.',
        remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
        conditionalWriteSupported: false,
      );
    }
    uploadedRemoteSyncBundle = true;
    return KnowledgeRemoteSyncUploadResult(
      snapshot: await buildSnapshot(),
      file: File('/tmp/knowledge_sync_bundle_v1.json'),
      remotePath: remotePath,
      uploadedAt: 200,
      createdRemote: false,
      rollbackSnapshotFile: File('/tmp/remote-rollback.json'),
      preview: _remotePreview(await buildSnapshot()),
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
    const remoteHistory = KnowledgeSyncEnvelope(
      id: 'remote-review-history',
      entityType: KnowledgeSyncEntityType.reviewHistory,
      schemaVersion: 1,
      updatedAt: 200,
      payload: {'id': 'remote-review-history'},
    );
    return KnowledgeRemoteSyncPreview(
      local: snapshot.included,
      remote: const [remoteIncoming, remoteHistory, remoteConflict],
      incoming: remotePreviewHasBlockers
          ? const [remoteIncoming, remoteHistory]
          : const <KnowledgeSyncEnvelope>[],
      outgoing: const <KnowledgeSyncEnvelope>[],
      conflicts: remotePreviewHasBlockers
          ? const [remoteConflict]
          : const <KnowledgeSyncEnvelope>[],
      remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
    );
  }
}
