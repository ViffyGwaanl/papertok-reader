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

  @override
  Future<KnowledgeAssetConflictReviewResult> submitConflictsToReview() async {
    submittedConflictsToReview = true;
    return KnowledgeAssetConflictReviewResult(
      submittedCount: 1,
      skippedCount: 0,
      snapshot: await buildSnapshot(),
    );
  }
}
