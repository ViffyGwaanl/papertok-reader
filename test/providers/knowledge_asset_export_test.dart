import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:papertok_reader/service/sync/sync_client_base.dart';

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
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remotePreview,
      isNotNull,
    );

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
    expect(state.lastSyncBundlePath, '/tmp/knowledge_sync_bundle_v1.json');
    expect(state.snapshot.value!.includedCount, 1);
    expect(state.remotePreview, isNull);
  });

  test('submitConflictsToReview exposes submitted conflict count', () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .submitConflictsToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.submittedConflictsToReview, true);
    expect(state.lastConflictReviewCount, 1);
    expect(state.snapshot.value!.conflictCount, 1);
  });

  test('previewRemoteSync exposes remote envelope conflict counts', () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.previewedRemoteSync, true);
    expect(state.remotePreview?.remoteCount, 3);
    expect(state.remotePreview?.incomingCount, 2);
    expect(state.remotePreview?.conflictCount, 1);

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    expect(container.read(knowledgeAssetExportProvider).remotePreview, isNull);
  });

  test('checkRemoteChanges is read-only and records latest check', () async {
    final service = _FakeKnowledgeAssetExportService();
    final notifier = KnowledgeAssetExportNotifier(
      service,
      clock: () => 123456789,
    );
    addTearDown(notifier.dispose);

    await notifier.checkRemoteChanges();
    final state = notifier.state;

    expect(service.previewedRemoteSync, true);
    expect(service.uploadedRemoteSyncBundle, false);
    expect(service.submittedRemoteConflictsToReview, false);
    expect(service.stagedRemoteKnowledgeCardConflictsToReview, false);
    expect(service.submittedRemoteIncomingToReview, false);
    expect(service.submittedRemoteReviewHistoryToReview, false);
    expect(state.lastRemoteCheckAt, 123456789);
    expect(state.remotePreview?.incomingCount, 2);
    expect(state.remotePreview?.conflictCount, 1);
    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.reviewRequired);
  });

  test('checkRemoteChanges failure clears stale preview without upload',
      () async {
    final service = _FakeKnowledgeAssetExportService();
    final notifier = KnowledgeAssetExportNotifier(
      service,
      clock: () => 123456789,
    );
    addTearDown(notifier.dispose);

    await notifier.checkRemoteChanges();
    expect(notifier.state.remotePreview, isNotNull);

    service.failRemotePreview = true;
    await notifier.checkRemoteChanges();
    final state = notifier.state;

    expect(service.uploadedRemoteSyncBundle, false);
    expect(state.remotePreview, isNull);
    expect(state.lastRemoteCheckAt, isNull);
    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.failed);
    expect(state.lastError, contains('remote unavailable'));
  });

  test('remote mutating actions clear stale read-only check state', () async {
    final service = _FakeKnowledgeAssetExportService();
    final notifier = KnowledgeAssetExportNotifier(
      service,
      clock: () => 123456789,
    );
    addTearDown(notifier.dispose);

    await notifier.checkRemoteChanges();
    expect(notifier.state.lastRemoteCheckAt, 123456789);

    await notifier.submitRemoteIncomingToReview();
    expect(service.submittedRemoteIncomingToReview, true);
    expect(notifier.state.lastRemoteCheckAt, isNull);

    await notifier.checkRemoteChanges();
    expect(notifier.state.lastRemoteCheckAt, 123456789);

    await notifier.uploadRemoteSyncBundle();
    expect(service.uploadedRemoteSyncBundle, true);
    expect(notifier.state.lastRemoteCheckAt, isNull);
  });

  test('remote sync status tracks preview blockers upload and failures',
      () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.notPreviewed,
    );

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.reviewRequired,
    );

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.uploaded,
    );

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.reviewRequired,
    );

    service.failRemotePreview = true;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.failed,
    );

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    expect(
      container.read(knowledgeAssetExportProvider).remoteSyncStatus,
      KnowledgeRemoteSyncStatus.notPreviewed,
    );
  });

  test('remote sync status is ready to upload without remote blockers',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..remotePreviewHasBlockers = false;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.remotePreview?.incomingCount, 0);
    expect(state.remotePreview?.conflictCount, 0);
    expect(
      state.remoteSyncStatus,
      KnowledgeRemoteSyncStatus.readyToUpload,
    );
  });

  test('submitRemoteConflictsToReview exposes submitted remote conflict count',
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
        .submitRemoteConflictsToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.submittedRemoteConflictsToReview, true);
    expect(state.lastRemoteConflictReviewCount, 1);
    expect(state.remotePreview?.conflictCount, 1);
  });

  test('stageRemoteKnowledgeCardConflictsToReview exposes staged count',
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
        .stageRemoteKnowledgeCardConflictsToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.stagedRemoteKnowledgeCardConflictsToReview, true);
    expect(state.lastRemoteConflictStageCount, 1);
    expect(state.lastRemoteConflictStageSkippedCount, 0);
    expect(state.remotePreview?.conflictCount, 1);
  });

  test('submitRemoteIncomingToReview exposes submitted incoming count',
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
        .submitRemoteIncomingToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.submittedRemoteIncomingToReview, true);
    expect(state.lastRemoteIncomingReviewCount, 1);
    expect(state.lastRemoteIncomingSkippedCount, 0);
    expect(state.remotePreview?.incomingCount, 2);
  });

  test('submitRemoteReviewHistoryToReview exposes submitted history count',
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
        .submitRemoteReviewHistoryToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.submittedRemoteReviewHistoryToReview, true);
    expect(state.lastRemoteReviewHistoryReviewCount, 1);
    expect(state.lastRemoteReviewHistorySkippedCount, 0);
    expect(state.remotePreview?.incomingCount, 2);
  });

  test('uploadRemoteSyncBundle exposes remote upload path and count', () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.uploadedRemoteSyncBundle, true);
    expect(state.lastRemoteUploadPath,
        KnowledgeAssetExportService.defaultRemoteSyncBundlePath);
    expect(state.lastRemoteUploadCount, 1);
    expect(state.snapshot.value?.includedCount, 1);
  });

  test('runSafeRemoteSync sends remote blockers to Review before upload',
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
        .runSafeRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.previewedRemoteSync, true);
    expect(service.stagedRemoteKnowledgeCardConflictsToReview, true);
    expect(service.submittedRemoteConflictsToReview, true);
    expect(service.submittedRemoteIncomingToReview, true);
    expect(service.submittedRemoteReviewHistoryToReview, true);
    expect(service.uploadedRemoteSyncBundle, false);
    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.reviewRequired);
    expect(state.lastRemoteConflictStageCount, 1);
    expect(state.lastRemoteConflictReviewCount, 1);
    expect(state.lastRemoteIncomingReviewCount, 1);
    expect(state.lastRemoteReviewHistoryReviewCount, 1);
    expect(state.remotePreview?.incomingCount, 2);
    expect(state.remotePreview?.conflictCount, 1);
  });

  test('runSafeRemoteSync uploads when preview has no remote blockers',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..remotePreviewHasBlockers = false;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .runSafeRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(service.previewedRemoteSync, true);
    expect(service.stagedRemoteKnowledgeCardConflictsToReview, false);
    expect(service.submittedRemoteIncomingToReview, false);
    expect(service.submittedRemoteReviewHistoryToReview, false);
    expect(service.uploadedRemoteSyncBundle, true);
    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.uploaded);
    expect(
      state.lastRemoteUploadPath,
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
    );
  });

  test('runSafeRemoteSync clears stale Review handoff counts on upload',
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
        .runSafeRemoteSync();
    expect(
      container
          .read(knowledgeAssetExportProvider)
          .lastRemoteIncomingReviewCount,
      1,
    );

    service.remotePreviewHasBlockers = false;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .runSafeRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.uploaded);
    expect(state.lastRemoteConflictReviewCount, isNull);
    expect(state.lastRemoteConflictStageCount, isNull);
    expect(state.lastRemoteIncomingReviewCount, isNull);
    expect(state.lastRemoteReviewHistoryReviewCount, isNull);
  });

  test('runSafeRemoteSync clears stale blocker counts between blocker shapes',
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
        .runSafeRemoteSync();
    expect(
      container
          .read(knowledgeAssetExportProvider)
          .lastRemoteConflictReviewCount,
      1,
    );

    service.remotePreviewHasConflict = false;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .runSafeRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.reviewRequired);
    expect(state.lastRemoteConflictReviewCount, isNull);
    expect(state.lastRemoteConflictStageCount, isNull);
    expect(state.lastRemoteIncomingReviewCount, 1);
    expect(state.lastRemoteReviewHistoryReviewCount, 1);
  });

  test('uploadRemoteSyncBundle exposes rollback state on writeback failure',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithRollback = true;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.failed);
    expect(state.lastRemoteRollbackRestored, true);
    expect(state.lastRemoteRollbackPath, '/tmp/remote-rollback.json');
    expect(state.lastError, contains('remote writeback failed'));
  });

  test('uploadRemoteSyncBundle maps remote precondition failure to repreview',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithPrecondition = true;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    final state = container.read(knowledgeAssetExportProvider);

    expect(
      state.remoteSyncStatus,
      KnowledgeRemoteSyncStatus.repreviewRequired,
    );
    expect(state.lastRemotePreconditionFailed, true);
    expect(state.lastError, contains('changed after preview'));
  });

  test('uploadRemoteSyncBundle maps unsupported CAS to guard unavailable',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithoutConditionalGuard = true;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    final state = container.read(knowledgeAssetExportProvider);

    expect(
      state.remoteSyncStatus,
      KnowledgeRemoteSyncStatus.concurrencyGuardUnavailable,
    );
    expect(state.lastRemoteConditionalWriteSupported, false);
    expect(state.lastError, contains('ETag/CAS'));
  });

  test('uploadRemoteSyncBundle clears stale rollback state on later success',
      () async {
    final service = _FakeKnowledgeAssetExportService()
      ..failRemoteWritebackWithRollback = true;
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    expect(
      container.read(knowledgeAssetExportProvider).lastRemoteRollbackPath,
      '/tmp/remote-rollback.json',
    );

    service
      ..failRemoteWritebackWithRollback = false
      ..remoteUploadRollbackSnapshotFile = null;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .uploadRemoteSyncBundle();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.remoteSyncStatus, KnowledgeRemoteSyncStatus.uploaded);
    expect(state.lastRemoteRollbackPath, isNull);
    expect(state.lastRemoteRollbackRestored, false);
    expect(state.lastRemotePartialRemoved, false);
    expect(state.lastError, isNull);
  });

  test('previewRemoteSync clears stale preview when remote read fails',
      () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remotePreview,
      isNotNull,
    );

    service.failRemotePreview = true;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.snapshot.value?.includedCount, 1);
    expect(state.snapshot.hasError, false);
    expect(state.remotePreview, isNull);
    expect(state.lastError, contains('remote unavailable'));
  });

  test('submitRemoteConflictsToReview clears stale preview when remote fails',
      () async {
    final service = _FakeKnowledgeAssetExportService();
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .previewRemoteSync();
    expect(
      container.read(knowledgeAssetExportProvider).remotePreview,
      isNotNull,
    );

    service.failRemotePreview = true;
    await container
        .read(knowledgeAssetExportProvider.notifier)
        .submitRemoteConflictsToReview();
    final state = container.read(knowledgeAssetExportProvider);

    expect(state.snapshot.value?.includedCount, 1);
    expect(state.snapshot.hasError, false);
    expect(state.remotePreview, isNull);
    expect(state.lastError, contains('remote unavailable'));
  });

  test('safe conflict flows from export provider to review apply', () async {
    final tempRoot = Directory.systemTemp.createTempSync();
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    final service = KnowledgeAssetExportService(
      rootDir: tempRoot,
      knowledgeCardStore: cardStore,
      reviewStore: reviewStore,
      spacedReviewStore: spacedReviewStore,
      now: () => 1000,
    );
    final reviewController = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      spacedReviewStore: spacedReviewStore,
      now: () => 1100,
    );
    final sourceRef = SourceRef(
      bookId: 42,
      href: 'Text/conflict.xhtml',
      cfi: 'epubcfi(/6/8)',
      jumpLink:
          'paperreader://reader/open?bookId=42&href=Text%2Fconflict.xhtml&cfi=epubcfi(%2F6%2F8)',
      sourceTitle: 'Conflict Book',
      locationLabel: 'Chapter 4',
      sourceTextSnippet: 'Traceable safe conflict evidence.',
      sourceKind: SourceRefKind.highlight,
      createdAt: 900,
    );
    final conflictCard = KnowledgeCard(
      id: 'kc-provider-conflict',
      title: 'Safe sync conflict',
      quote: 'Traceable safe conflict evidence.',
      explanation: 'Remote safe card needs review before export.',
      sourceRefs: [sourceRef],
      reviewState: KnowledgeCardReviewState.applied,
      origin: KnowledgeCardOrigin.selection,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      createdAt: 900,
      updatedAt: 900,
    );
    final conflictEnvelope = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 900,
      sourceRefs: conflictCard.sourceRefs,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      payload: conflictCard.toJson(),
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [conflictEnvelope.toJson()],
      }),
    );
    final container = ProviderContainer(
      overrides: [
        knowledgeAssetExportServiceProvider.overrideWithValue(service),
        reviewInboxControllerProvider.overrideWithValue(reviewController),
      ],
    );
    addTearDown(container.dispose);

    await container.read(knowledgeAssetExportProvider.notifier).refresh();
    expect(
        container.read(knowledgeAssetExportProvider).snapshot.value, isNotNull);
    expect(
      container
          .read(knowledgeAssetExportProvider)
          .snapshot
          .value!
          .conflictCount,
      1,
    );

    await container
        .read(knowledgeAssetExportProvider.notifier)
        .submitConflictsToReview();
    expect(
      container.read(knowledgeAssetExportProvider).lastConflictReviewCount,
      1,
    );

    final reviewId = 'sync-conflict:${conflictCard.id}';
    await container.read(reviewInboxProvider.notifier).refresh();
    expect(
      container.read(reviewInboxProvider).items.value!.map((item) => item.id),
      contains(reviewId),
    );

    await container.read(reviewInboxProvider.notifier).approve(reviewId);
    await container
        .read(reviewInboxProvider.notifier)
        .setStatusFilter(ReviewItemStatus.approved);
    expect(
      container.read(reviewInboxProvider).items.value!.single.status,
      ReviewItemStatus.approved,
    );

    await container.read(reviewInboxProvider.notifier).apply(reviewId);
    final appliedReview = await reviewStore.getById(reviewId);
    final resolvedEnvelope = (await cardStore.listSyncEnvelopes()).single;
    final snapshot = await service.buildSnapshot();

    expect(appliedReview?.status, ReviewItemStatus.applied);
    expect(resolvedEnvelope.requiresConflictReview, false);
    expect(await spacedReviewStore.list(), isEmpty);
    expect(
      snapshot.included.map((envelope) => envelope.id),
      contains(conflictCard.id),
    );
    expect(
      snapshot.excluded.map((envelope) => envelope.id),
      isNot(contains(conflictCard.id)),
    );
  });
}

class _FakeKnowledgeAssetExportService extends KnowledgeAssetExportService {
  _FakeKnowledgeAssetExportService()
      : super(rootDir: Directory.systemTemp.createTempSync());

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
  File? remoteUploadRollbackSnapshotFile = File('/tmp/remote-rollback.json');
  bool remotePreviewHasBlockers = true;
  bool remotePreviewHasIncoming = true;
  bool remotePreviewHasConflict = true;

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
      rollbackSnapshotFile: remoteUploadRollbackSnapshotFile,
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
      incoming: remotePreviewHasBlockers && remotePreviewHasIncoming
          ? const [remoteIncoming, remoteHistory]
          : const <KnowledgeSyncEnvelope>[],
      outgoing: const <KnowledgeSyncEnvelope>[],
      conflicts: remotePreviewHasBlockers && remotePreviewHasConflict
          ? const [remoteConflict]
          : const <KnowledgeSyncEnvelope>[],
      remotePath: KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
    );
  }
}
