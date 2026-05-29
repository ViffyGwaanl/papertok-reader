import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late SpacedReviewStore spacedReviewStore;
  late KnowledgeAssetExportService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'knowledge_asset_export_',
    );
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    service = KnowledgeAssetExportService(
      rootDir: tempRoot,
      knowledgeCardStore: cardStore,
      spacedReviewStore: spacedReviewStore,
      now: () => 1000,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 7,
    String cfi = 'epubcfi(/6/8)',
    String snippet = 'Traceable export evidence.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: 'Text/chapter.xhtml',
        cfi: cfi,
        jumpLink: 'paperreader://reader/open?bookId=$bookId&cfi=$cfi',
        sourceTextSnippet: List.filled(700, snippet).join(' '),
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({
    required String id,
    KnowledgeCardReviewState reviewState = KnowledgeCardReviewState.pending,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    List<SourceRef>? sourceRefs,
    String quote = 'Traceable export evidence.',
  }) =>
      KnowledgeCard(
        id: id,
        title: 'Exportable card $id',
        quote: quote,
        explanation: 'Export should preserve source refs safely.',
        sourceRefs: sourceRefs ?? [traceableRef()],
        reviewState: reviewState,
        ownership: ownership,
        createdAt: 100,
        updatedAt: 100,
      );

  Future<KnowledgeCard> stageAppliedCard(String id) async {
    final staged = await cardStore.upsertCandidate(card(id: id));
    final pending = KnowledgeCardReviewAdapter.fromKnowledgeCard(staged.card);
    final approved = pending.transitionTo(
      ReviewItemStatus.approved,
      now: 200,
      decisionSource: 'user_approve',
    );
    final applied = approved.transitionTo(
      ReviewItemStatus.applied,
      now: 300,
      decisionSource: 'user_apply',
    );
    await cardStore.applyReviewDecision(approved, now: 200);
    return cardStore.applyReviewDecision(applied, now: 300);
  }

  test('plans safe export for applied cards and review history only', () async {
    final applied = await stageAppliedCard('kc-export');
    await cardStore.upsertCandidate(
      card(
        id: 'kc-draft',
        quote: 'Draft-only evidence.',
        sourceRefs: [
          traceableRef(
            cfi: 'epubcfi(/6/20)',
            snippet: 'Draft-only evidence.',
          ),
        ],
      ),
    );
    final review = await spacedReviewStore.upsertFromKnowledgeCard(
      applied,
      now: 400,
    );
    await spacedReviewStore.recordReview(
      review.id,
      rating: SpacedReviewRating.good,
      now: 500,
    );

    final snapshot = await service.buildSnapshot();

    expect(
      snapshot.included.map((envelope) => envelope.entityType),
      [
        KnowledgeSyncEntityType.knowledgeCard,
        KnowledgeSyncEntityType.reviewHistory,
      ],
    );
    expect(snapshot.excluded.map((envelope) => envelope.id), ['kc-draft']);
    expect(snapshot.excludedReasonFor('kc-draft'), 'not-default-sync-entity');
    expect(snapshot.manifest.safeByDefault, true);
    expect(snapshot.manifest.entityIds, [
      'kc-export',
      SpacedReviewStore.reviewIdForCard('kc-export'),
    ]);
    expect(snapshot.manifest.formats, contains(KnowledgeExportFormat.markdown));
    expect(
      snapshot.manifest.formats,
      contains(KnowledgeExportFormat.sourceCitationManifest),
    );
    expect(
      snapshot.manifest.sourceRefs.first.sourceTextSnippet!.length,
      lessThanOrEqualTo(SourceRef.maxSnippetChars),
    );
  });

  test('writes export manifest without drafts derived cache or secrets',
      () async {
    await stageAppliedCard('kc-export');

    final result = await service.writeManifest();
    final decoded =
        jsonDecode(await result.file.readAsString()) as Map<String, dynamic>;

    expect(result.file.path, endsWith('knowledge_export_manifest_v1.json'));
    expect(decoded['id'], 'knowledge-export-1000');
    expect(decoded['includeDrafts'], false);
    expect(decoded['includeFullEvidenceText'], false);
    expect(decoded['entityIds'], ['kc-export']);
    expect(jsonEncode(decoded), isNot(contains('apiKey')));
    expect(jsonEncode(decoded), isNot(contains('ai_index.db')));
  });

  test('writes readable markdown export for included user assets only',
      () async {
    await stageAppliedCard('kc-export');
    await cardStore.upsertCandidate(
      card(
        id: 'kc-draft',
        quote: 'Draft-only evidence should not export.',
        sourceRefs: [
          traceableRef(
            cfi: 'epubcfi(/6/20)',
            snippet: 'Draft-only evidence should not export.',
          ),
        ],
      ),
    );

    final result = await service.writeManifest();

    expect(result.markdownFile, isNotNull);
    expect(result.markdownFile!.path, endsWith('knowledge_export_v1.md'));
    final markdown = await result.markdownFile!.readAsString();
    expect(markdown, contains('# PaperTok Knowledge Export'));
    expect(markdown, contains('## Exportable card kc-export'));
    expect(markdown, contains('> Traceable export evidence.'));
    expect(markdown, contains('Export should preserve source refs safely.'));
    expect(markdown, contains('paperreader://reader/open?bookId=7'));
    final snippetLine = markdown
        .split('\n')
        .firstWhere((line) => line.trimLeft().startsWith('- Snippet:'));
    final snippet = snippetLine.substring(snippetLine.indexOf(':') + 1).trim();
    expect(snippet.length, lessThanOrEqualTo(SourceRef.maxSnippetChars));
    expect(markdown, isNot(contains('kc-draft')));
    expect(markdown, isNot(contains('Draft-only evidence should not export')));
    expect(markdown, isNot(contains('apiKey')));
    expect(markdown, isNot(contains('ai_index.db')));
  });

  test('markdown ignores excluded conflict secret and derived cache envelopes',
      () async {
    final includedCard = card(
      id: 'kc-included',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Included card evidence.',
    );
    final snapshot = KnowledgeAssetExportSnapshot(
      manifest: const KnowledgeExportManifest(
        id: 'knowledge-export-test',
        createdAt: 1000,
        formats: [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: ['kc-included'],
      ),
      included: [
        KnowledgeSyncEnvelope(
          id: includedCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 1000,
          sourceRefs: includedCard.sourceRefs,
          payload: includedCard.toJson(),
        ),
      ],
      excluded: [
        KnowledgeSyncEnvelope(
          id: 'kc-conflict',
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 1000,
          conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
          conflictReason: 'content-conflict',
          sourceRefs: [traceableRef(snippet: 'Conflict should stay out.')],
          payload: card(
            id: 'kc-conflict',
            quote: 'Conflict should stay out.',
          ).toJson(),
        ),
        const KnowledgeSyncEnvelope(
          id: 'secret-envelope',
          entityType: KnowledgeSyncEntityType.secret,
          schemaVersion: 1,
          updatedAt: 1000,
          payload: {'apiKey': 'super-secret-value'},
        ),
        const KnowledgeSyncEnvelope(
          id: 'derived-cache',
          entityType: KnowledgeSyncEntityType.derivedIndex,
          schemaVersion: 1,
          updatedAt: 1000,
          payload: {'path': 'ai_index.db'},
        ),
      ],
      excludedReasons: const {
        'kc-conflict': 'pending-conflict-review',
        'secret-envelope': 'contains-secret',
        'derived-cache': 'not-default-sync-entity',
      },
    );
    final fakeService = _SnapshotKnowledgeAssetExportService(
      rootDir: tempRoot,
      snapshot: snapshot,
    );

    final result = await fakeService.writeManifest();
    final markdown = await result.markdownFile!.readAsString();

    expect(markdown, contains('Included card evidence.'));
    expect(markdown, isNot(contains('Conflict should stay out')));
    expect(markdown, isNot(contains('super-secret-value')));
    expect(markdown, isNot(contains('ai_index.db')));
    expect(markdown, isNot(contains('derived-cache')));
  });

  test('holds persisted conflict envelopes out of export manifest', () async {
    final conflictCard = card(
      id: 'kc-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    final conflict = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      sourceRefs: conflictCard.sourceRefs,
      payload: conflictCard.toJson(),
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [conflict.toJson()],
      }),
    );

    final snapshot = await service.buildSnapshot();

    expect(snapshot.included, isEmpty);
    expect(snapshot.excluded.single.id, 'kc-conflict');
    expect(
      snapshot.excludedReasonFor('kc-conflict'),
      'pending-conflict-review',
    );
    expect(snapshot.manifest.entityIds, isNot(contains('kc-conflict')));
  });
}

class _SnapshotKnowledgeAssetExportService extends KnowledgeAssetExportService {
  _SnapshotKnowledgeAssetExportService({
    required Directory rootDir,
    required this.snapshot,
  }) : super(rootDir: rootDir);

  final KnowledgeAssetExportSnapshot snapshot;

  @override
  Future<KnowledgeAssetExportSnapshot> buildSnapshot({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    return snapshot;
  }
}
