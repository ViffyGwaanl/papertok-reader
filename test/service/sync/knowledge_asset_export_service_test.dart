import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/remote_file.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:papertok_reader/service/sync/sync_client_base.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late ReviewItemStore reviewStore;
  late SpacedReviewStore spacedReviewStore;
  late KnowledgeAssetExportService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'knowledge_asset_export_',
    );
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    spacedReviewStore = SpacedReviewStore(rootDir: tempRoot);
    service = KnowledgeAssetExportService(
      rootDir: tempRoot,
      knowledgeCardStore: cardStore,
      reviewStore: reviewStore,
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
    String? title,
    KnowledgeCardReviewState reviewState = KnowledgeCardReviewState.pending,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    List<SourceRef>? sourceRefs,
    String quote = 'Traceable export evidence.',
    String explanation = 'Export should preserve source refs safely.',
    String? userNote,
    List<String> conceptRefs = const <String>[],
  }) =>
      KnowledgeCard(
        id: id,
        title: title ?? 'Exportable card $id',
        quote: quote,
        explanation: explanation,
        userNote: userNote,
        sourceRefs: sourceRefs ?? [traceableRef()],
        conceptRefs: conceptRefs,
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
    expect(snapshot.manifest.formats, contains(KnowledgeExportFormat.html));
    expect(snapshot.manifest.formats, contains(KnowledgeExportFormat.anki));
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

  test('writes machine readable sync bundle for included user assets only',
      () async {
    await stageAppliedCard('kc-export');
    await cardStore.upsertCandidate(
      card(
        id: 'kc-draft',
        quote: 'Draft-only evidence should not sync.',
        sourceRefs: [
          traceableRef(
            cfi: 'epubcfi(/6/20)',
            snippet: 'Draft-only evidence should not sync.',
          ),
        ],
      ),
    );

    final result = await service.writeManifest();

    expect(result.syncBundleFile, isNotNull);
    expect(
        result.syncBundleFile!.path, endsWith('knowledge_sync_bundle_v1.json'));
    final decoded = jsonDecode(await result.syncBundleFile!.readAsString())
        as Map<String, dynamic>;
    final encoded = jsonEncode(decoded);
    expect(decoded['schemaVersion'], 1);
    expect(decoded['createdAt'], 1000);
    expect((decoded['envelopes'] as List), hasLength(1));
    expect(encoded, contains('kc-export'));
    expect(encoded, isNot(contains('kc-draft')));
    expect(encoded, isNot(contains('Draft-only evidence should not sync')));
    expect(encoded, isNot(contains('apiKey')));
    expect(encoded, isNot(contains('ai_index.db')));
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

  test('writes html study report for included user assets only', () async {
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

    expect(result.htmlReportFile, isNotNull);
    expect(
      result.htmlReportFile!.path,
      endsWith('knowledge_export_study_report.html'),
    );
    final html = await result.htmlReportFile!.readAsString();
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<main'));
    expect(html, contains('PaperTok Knowledge Study Report'));
    expect(html, contains('Exportable card kc-export'));
    expect(html, contains('Traceable export evidence.'));
    expect(html, contains('Export should preserve source refs safely.'));
    expect(html, contains('paperreader://reader/open?bookId=7'));
    expect(html, isNot(contains('kc-draft')));
    expect(html, isNot(contains('Draft-only evidence should not export')));
    expect(html, isNot(contains('apiKey')));
    expect(html, isNot(contains('ai_index.db')));
  });

  test('writes anki compatible tsv for included user assets only', () async {
    final applied = await stageAppliedCard('kc-export');
    final review = await spacedReviewStore.upsertFromKnowledgeCard(
      applied,
      now: 400,
    );
    await spacedReviewStore.recordReview(
      review.id,
      rating: SpacedReviewRating.good,
      now: 500,
    );
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

    expect(result.ankiFile, isNotNull);
    expect(result.ankiFile!.path, endsWith('knowledge_export_anki.tsv'));
    final anki = await result.ankiFile!.readAsString();
    expect(anki, startsWith('#separator:tab\n#html:true'));
    expect(anki, contains('Front\tBack\tSource'));
    expect(anki, contains('Exportable card kc-export'));
    expect(anki, contains('Traceable export evidence.'));
    expect(anki, contains('Export should preserve source refs safely.'));
    expect(anki, contains('paperreader://reader/open?bookId=7'));
    expect(anki, isNot(contains('kc-draft')));
    expect(anki, isNot(contains('Draft-only evidence should not export')));
    expect(anki, isNot(contains('apiKey')));
    expect(anki, isNot(contains('ai_index.db')));
  });

  test('anki export escapes html tabs and newlines without breaking columns',
      () async {
    final specialCard = card(
      id: 'kc-special',
      title: 'Front\t<title>&',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Quote\tline <one>\nline & two',
      explanation: 'Explain > result',
      userNote: 'User\tnote',
      conceptRefs: const ['Graph <RAG>'],
      sourceRefs: [
        traceableRef(
          snippet: 'Snippet\twith <html>\nsecond & line',
        ),
      ],
    );
    final snapshot = KnowledgeAssetExportSnapshot(
      manifest: KnowledgeExportManifest(
        id: 'knowledge-export-test',
        createdAt: 1000,
        formats: const [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.anki,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: [specialCard.id],
        sourceRefs: specialCard.sourceRefs,
      ),
      included: [
        KnowledgeSyncEnvelope(
          id: specialCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 1000,
          sourceRefs: specialCard.sourceRefs,
          payload: specialCard.toJson(),
        ),
      ],
      excluded: const [],
      excludedReasons: const {},
    );
    final fakeService = _SnapshotKnowledgeAssetExportService(
      rootDir: tempRoot,
      snapshot: snapshot,
    );

    final result = await fakeService.writeManifest();
    final lines = (await result.ankiFile!.readAsString()).trim().split('\n');
    final row = lines.singleWhere((line) => line.startsWith('Front '));
    final columns = row.split('\t');

    expect(columns, hasLength(3));
    expect(columns[0], 'Front &lt;title&gt;&amp;');
    expect(columns[1], contains('Quote line &lt;one&gt;<br>line &amp; two'));
    expect(columns[1], contains('Explain &gt; result'));
    expect(columns[1], contains('User note'));
    expect(columns[1], contains('Concepts: Graph &lt;RAG&gt;'));
    expect(columns[2], contains('Snippet with &lt;html&gt;'));
    expect(columns[2], contains('second &amp; line'));
    expect(row, isNot(contains('<title>&')));
  });

  test('html study report escapes html content', () async {
    final specialCard = card(
      id: 'kc-special',
      title: 'Front <script>alert(1)</script> & title',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Quote <em>unsafe</em> & raw',
      explanation: 'Explain > result',
      userNote: 'User <note>',
      conceptRefs: const ['Graph <RAG>'],
      sourceRefs: [
        traceableRef(
          snippet: 'Snippet with <html>\nsecond & line',
        ),
      ],
    );
    final snapshot = KnowledgeAssetExportSnapshot(
      manifest: KnowledgeExportManifest(
        id: 'knowledge-export-test',
        createdAt: 1000,
        formats: const [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.html,
          KnowledgeExportFormat.anki,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: [specialCard.id],
        sourceRefs: specialCard.sourceRefs,
      ),
      included: [
        KnowledgeSyncEnvelope(
          id: specialCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 1000,
          sourceRefs: specialCard.sourceRefs,
          payload: specialCard.toJson(),
        ),
      ],
      excluded: const [],
      excludedReasons: const {},
    );
    final fakeService = _SnapshotKnowledgeAssetExportService(
      rootDir: tempRoot,
      snapshot: snapshot,
    );

    final result = await fakeService.writeManifest();
    final html = await result.htmlReportFile!.readAsString();

    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('<em>unsafe</em>')));
    expect(html, contains('Front &lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(html, contains('Quote &lt;em&gt;unsafe&lt;/em&gt; &amp; raw'));
    expect(html, contains('Explain &gt; result'));
    expect(html, contains('User &lt;note&gt;'));
    expect(html, contains('Graph &lt;RAG&gt;'));
    expect(html, contains('Snippet with &lt;html&gt;'));
    expect(html, contains('second &amp; line'));
  });

  test('html study report does not render invalid jump links', () async {
    final specialCard = card(
      id: 'kc-invalid-link',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Included evidence.',
      sourceRefs: [
        SourceRef(
          bookId: 7,
          href: 'Text/chapter.xhtml',
          jumpLink: 'javascript:alert(1)',
          sourceTextSnippet: 'Safe snippet.',
          sourceKind: SourceRefKind.highlight,
        ),
      ],
    );
    final snapshot = KnowledgeAssetExportSnapshot(
      manifest: KnowledgeExportManifest(
        id: 'knowledge-export-test',
        createdAt: 1000,
        formats: const [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.html,
          KnowledgeExportFormat.anki,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: [specialCard.id],
        sourceRefs: specialCard.sourceRefs,
      ),
      included: [
        KnowledgeSyncEnvelope(
          id: specialCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 1000,
          sourceRefs: specialCard.sourceRefs,
          payload: specialCard.toJson(),
        ),
      ],
      excluded: const [],
      excludedReasons: const {},
    );
    final fakeService = _SnapshotKnowledgeAssetExportService(
      rootDir: tempRoot,
      snapshot: snapshot,
    );

    final result = await fakeService.writeManifest();
    final html = await result.htmlReportFile!.readAsString();

    expect(html, contains('Safe snippet.'));
    expect(html, isNot(contains('javascript:alert')));
    expect(html, isNot(contains('<a href=')));
  });

  test('exports ignore excluded conflict secret and derived cache envelopes',
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
          KnowledgeExportFormat.html,
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
    final anki = await result.ankiFile!.readAsString();
    expect(anki, contains('Included card evidence.'));
    expect(anki, isNot(contains('Conflict should stay out')));
    expect(anki, isNot(contains('super-secret-value')));
    expect(anki, isNot(contains('ai_index.db')));
    expect(anki, isNot(contains('derived-cache')));
    final html = await result.htmlReportFile!.readAsString();
    expect(html, contains('Included card evidence.'));
    expect(html, isNot(contains('Conflict should stay out')));
    expect(html, isNot(contains('super-secret-value')));
    expect(html, isNot(contains('ai_index.db')));
    expect(html, isNot(contains('derived-cache')));
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

  test('submits pending sync conflicts to review without raw payload secrets',
      () async {
    final conflictCard = card(
      id: 'kc-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Conflict evidence.',
    );
    final conflict = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      sourceRefs: conflictCard.sourceRefs,
      payload: {
        ...conflictCard.toJson(),
        'apiKey': 'redacted-sentinel-must-not-enter-review',
      },
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [conflict.toJson()],
      }),
    );

    final result = await service.submitConflictsToReview();
    final items = await reviewStore.list(
      sourceType: ReviewItemSourceType.syncConflict,
    );

    expect(result.submittedCount, 1);
    expect(result.skippedCount, 0);
    expect(items, hasLength(1));
    expect(items.single.id, 'sync-conflict:kc-conflict');
    expect(items.single.status, ReviewItemStatus.pending);
    expect(items.single.sourceId, 'kc-conflict');
    expect(items.single.title, contains('kc-conflict'));
    expect(items.single.body, contains('content-conflict'));
    expect(items.single.sourceRefs.single.sourceTextSnippet, isNotEmpty);
    expect(items.single.payload['entityId'], 'kc-conflict');
    expect(items.single.payload['entityType'], 'knowledge-card');
    expect(items.single.payload['canApply'], false);
    expect(items.single.payload['payloadKeys'], contains('apiKey'));
    expect(
      jsonEncode(items.single.payload),
      isNot(contains('redacted-sentinel')),
    );
  });

  test('marks safe knowledge card sync conflicts as applyable', () async {
    final conflictCard = card(
      id: 'kc-safe-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Traceable safe conflict evidence.',
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

    await service.submitConflictsToReview();
    final item = (await reviewStore.list(
      sourceType: ReviewItemSourceType.syncConflict,
    ))
        .single;

    expect(item.payload['canApply'], true);
    expect(item.payload['entityType'], 'knowledge-card');
    expect(item.sourceRefs.single.hasBookAnchor, true);
  });

  test('submitted sync conflict can be approved applied and exported',
      () async {
    final conflictCard = card(
      id: 'kc-safe-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Traceable safe conflict evidence.',
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

    final submitted = await service.submitConflictsToReview();
    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      spacedReviewStore: spacedReviewStore,
      now: () => 1100,
    );
    final reviewId = 'sync-conflict:${conflictCard.id}';

    expect(submitted.submittedCount, 1);
    expect(await reviewStore.getById(reviewId), isNotNull);

    await controller.approve(reviewId);
    final applied = await controller.apply(reviewId);
    final resolvedCard = await cardStore.getById(conflictCard.id);
    final snapshot = await service.buildSnapshot();

    expect(applied.status, ReviewItemStatus.applied);
    expect(resolvedCard?.reviewState, KnowledgeCardReviewState.applied);
    expect(resolvedCard?.ownership, AiOutputOwnership.aiGeneratedApproved);
    expect(
      snapshot.included.map((envelope) => envelope.id),
      contains(conflictCard.id),
    );
    expect(
      snapshot.excluded.map((envelope) => envelope.id),
      isNot(contains(conflictCard.id)),
    );
  });

  test('remote sync preview detects conflicts and submits them to review',
      () async {
    final localCard = await stageAppliedCard('kc-shared');
    final remoteConflictCard = card(
      id: localCard.id,
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Remote changed evidence.',
      explanation: 'Remote changed explanation.',
      sourceRefs: [
        traceableRef(snippet: 'Remote changed evidence.'),
      ],
    );
    final remoteIncomingCard = card(
      id: 'kc-remote-new',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Remote new evidence.',
      explanation: 'Remote new explanation.',
      sourceRefs: [
        traceableRef(
          bookId: 9,
          cfi: 'epubcfi(/6/30)',
          snippet: 'Remote new evidence.',
        ),
      ],
    );
    final remoteBundle = jsonEncode({
      'schemaVersion': 1,
      'createdAt': 2000,
      'envelopes': [
        KnowledgeSyncEnvelope(
          id: remoteConflictCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 2000,
          sourceRefs: remoteConflictCard.sourceRefs,
          payload: remoteConflictCard.toJson(),
        ).toJson(),
        KnowledgeSyncEnvelope(
          id: remoteIncomingCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 2000,
          sourceRefs: remoteIncomingCard.sourceRefs,
          payload: remoteIncomingCard.toJson(),
        ).toJson(),
      ],
    });
    final remoteClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: remoteBundle,
    });

    final preview = await service.previewRemoteSync(client: remoteClient);

    expect(preview.localCount, 1);
    expect(preview.remoteCount, 2);
    expect(preview.incoming.map((envelope) => envelope.id), ['kc-remote-new']);
    expect(preview.outgoing, isEmpty);
    expect(preview.conflicts.map((envelope) => envelope.id), ['kc-shared']);
    expect(preview.conflicts.single.conflictReason, 'content-conflict');
    expect(
      await reviewStore.list(sourceType: ReviewItemSourceType.syncConflict),
      isEmpty,
    );

    final submitted = await service.submitRemoteConflictsToReview(
      client: remoteClient,
    );
    final items = await reviewStore.list(
      sourceType: ReviewItemSourceType.syncConflict,
    );

    expect(submitted.submittedCount, 1);
    expect(submitted.skippedCount, 0);
    expect(items, hasLength(1));
    expect(items.single.id, 'sync-conflict:kc-shared');
    expect(items.single.payload['canApply'], false);
    expect(items.single.payload['remotePreviewOnly'], true);
    expect(items.single.payload['excludedReason'], 'remote-sync-preview');
    expect(items.single.payload['entityType'], 'knowledge-card');
    expect(items.single.sourceRefs.single.hasBookAnchor, true);
    expect(jsonEncode(items.single.payload),
        isNot(contains('Remote changed explanation')));
    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      spacedReviewStore: spacedReviewStore,
    );
    await expectLater(
      controller.approve(items.single.id),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('remote sync upload writes bundle only when remote has no blockers',
      () async {
    await stageAppliedCard('kc-upload');
    final remoteClient = _FakeSyncClient(<String, String>{});

    final uploaded = await service.uploadRemoteSyncBundle(
      client: remoteClient,
    );

    expect(uploaded.remotePath,
        KnowledgeAssetExportService.defaultRemoteSyncBundlePath);
    expect(uploaded.uploadedCount, 1);
    expect(uploaded.createdRemote, true);
    expect(remoteClient.safeReadDirs, ['paper_reader/.knowledge']);
    expect(remoteClient.createdDirs, ['paper_reader/.knowledge']);
    expect(
      remoteClient.uploadedPaths,
      [KnowledgeAssetExportService.defaultRemoteSyncBundlePath],
    );
    final remoteBundle = jsonDecode(remoteClient
            .files[KnowledgeAssetExportService.defaultRemoteSyncBundlePath]!)
        as Map<String, dynamic>;
    expect(jsonEncode(remoteBundle), contains('kc-upload'));
    expect(jsonEncode(remoteBundle), isNot(contains('apiKey')));

    final secondUpload = await service.uploadRemoteSyncBundle(
      client: remoteClient,
    );
    expect(secondUpload.createdRemote, false);
    expect(secondUpload.preview?.incomingCount, 0);
    expect(secondUpload.preview?.conflictCount, 0);
    expect(remoteClient.uploadedPaths, [
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath,
    ]);
  });

  test('remote incoming knowledge cards are staged as review candidates',
      () async {
    final remoteCard = card(
      id: 'kc-remote-incoming',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Remote incoming evidence.',
      explanation: 'Remote incoming card requires local review.',
      sourceRefs: [
        traceableRef(
          bookId: 12,
          cfi: 'epubcfi(/6/42)',
          snippet: 'Remote incoming evidence.',
        ),
      ],
    );
    final remoteClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: jsonEncode({
        'schemaVersion': 1,
        'createdAt': 2000,
        'envelopes': [
          KnowledgeSyncEnvelope(
            id: remoteCard.id,
            entityType: KnowledgeSyncEntityType.knowledgeCard,
            schemaVersion: 1,
            updatedAt: 2000,
            sourceRefs: remoteCard.sourceRefs,
            payload: remoteCard.toJson(),
          ).toJson(),
        ],
      }),
    });

    final result = await service.submitRemoteIncomingToReview(
      client: remoteClient,
    );

    expect(result.submittedCount, 1);
    expect(result.skippedCount, 0);
    expect(result.remotePreview.incomingCount, 1);
    final cards = await cardStore.list();
    expect(cards, hasLength(1));
    expect(cards.single.id, remoteCard.id);
    expect(cards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(cards.single.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(cards.single.isUserAsset, false);
    final items = await reviewStore.list(
      sourceType: ReviewItemSourceType.knowledgeCard,
    );
    expect(items, hasLength(1));
    expect(items.single.id, 'knowledge-card:${remoteCard.id}');
    expect(items.single.status, ReviewItemStatus.pending);
    expect(items.single.sourceRefs.single.hasBookAnchor, true);
    expect(jsonEncode(items.single.payload), isNot(contains('apiKey')));

    final secondResult = await service.submitRemoteIncomingToReview(
      client: remoteClient,
    );
    expect(secondResult.submittedCount, 0);
    expect(secondResult.skippedCount, 1);
    expect(await cardStore.list(), hasLength(1));
    expect(
      await reviewStore.list(sourceType: ReviewItemSourceType.knowledgeCard),
      hasLength(1),
    );
  });

  test('remote incoming review skips unsupported and untraceable envelopes',
      () async {
    final untraceableCard = card(
      id: 'kc-untraceable-remote',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      sourceRefs: const <SourceRef>[],
    );
    final remoteClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: jsonEncode({
        'schemaVersion': 1,
        'createdAt': 2000,
        'envelopes': [
          KnowledgeSyncEnvelope(
            id: untraceableCard.id,
            entityType: KnowledgeSyncEntityType.knowledgeCard,
            schemaVersion: 1,
            updatedAt: 2000,
            payload: untraceableCard.toJson(),
          ).toJson(),
          const KnowledgeSyncEnvelope(
            id: 'remote-review-history',
            entityType: KnowledgeSyncEntityType.reviewHistory,
            schemaVersion: 1,
            updatedAt: 2000,
            payload: {'id': 'remote-review-history'},
          ).toJson(),
        ],
      }),
    });

    final result = await service.submitRemoteIncomingToReview(
      client: remoteClient,
    );

    expect(result.submittedCount, 0);
    expect(result.skippedCount, 2);
    expect(await cardStore.list(), isEmpty);
    expect(
      await reviewStore.list(sourceType: ReviewItemSourceType.knowledgeCard),
      isEmpty,
    );
  });

  test('remote review history is applied only after Review approval', () async {
    final remoteHistory = SpacedReviewItem(
      id: SpacedReviewStore.reviewIdForCard('kc-remote-review'),
      cardId: 'kc-remote-review',
      prompt: 'Remote review prompt',
      answer: 'Remote review answer',
      sourceRefs: [traceableRef(snippet: 'Remote review evidence.')],
      lastReviewedAt: 2000,
      dueAt: 2000 + Duration.millisecondsPerDay * 3,
      intervalDays: 3,
      reviewHistory: const [
        SpacedReviewHistoryEntry(
          reviewedAt: 2000,
          rating: 'good',
          intervalDays: 3,
        ),
      ],
    );
    final remoteClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: jsonEncode({
        'schemaVersion': 1,
        'createdAt': 2000,
        'envelopes': [
          KnowledgeSyncEnvelope(
            id: remoteHistory.id,
            entityType: KnowledgeSyncEntityType.reviewHistory,
            schemaVersion: 1,
            updatedAt: 2000,
            sourceRefs: remoteHistory.sourceRefs,
            payload: remoteHistory.toJson(),
          ).toJson(),
        ],
      }),
    });

    final result = await service.submitRemoteReviewHistoryToReview(
      client: remoteClient,
    );

    expect(result.submittedCount, 1);
    expect(result.skippedCount, 0);
    expect(result.remotePreview.incomingCount, 1);
    expect(await spacedReviewStore.list(), isEmpty);
    final reviewItems = await reviewStore.list(
      sourceType: ReviewItemSourceType.reviewHistoryImport,
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.status, ReviewItemStatus.pending);
    expect(reviewItems.single.sourceId, remoteHistory.id);
    expect(reviewItems.single.sourceRefs.single.hasEvidence, true);
    expect(
      jsonEncode(reviewItems.single.payload),
      isNot(contains('apiKey')),
    );

    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      spacedReviewStore: spacedReviewStore,
    );
    await controller.approve(reviewItems.single.id);
    await controller.apply(reviewItems.single.id);

    final imported = await spacedReviewStore.getById(remoteHistory.id);
    final applied = await reviewStore.getById(reviewItems.single.id);
    expect(imported?.lastReviewedAt, 2000);
    expect(imported?.reviewHistory.single.rating, 'good');
    expect(applied?.status, ReviewItemStatus.applied);
  });

  test('remote review history skips duplicate unsafe and untraceable entries',
      () async {
    final safeHistory = SpacedReviewItem(
      id: SpacedReviewStore.reviewIdForCard('kc-safe-history'),
      cardId: 'kc-safe-history',
      prompt: 'Safe prompt',
      answer: 'Safe answer',
      sourceRefs: [traceableRef(snippet: 'Safe remote review evidence.')],
      lastReviewedAt: 2000,
      dueAt: 2000,
      intervalDays: 3,
    );
    final unsafeHistory = SpacedReviewItem(
      id: SpacedReviewStore.reviewIdForCard('kc-unsafe-history'),
      cardId: 'kc-unsafe-history',
      prompt: 'Unsafe prompt',
      answer: 'Unsafe answer',
      sourceRefs: [traceableRef(snippet: 'Unsafe remote review evidence.')],
    );
    final untraceableHistory = SpacedReviewItem(
      id: SpacedReviewStore.reviewIdForCard('kc-untraceable-history'),
      cardId: 'kc-untraceable-history',
      prompt: 'Untraceable prompt',
      answer: 'Untraceable answer',
      sourceRefs: const <SourceRef>[],
    );
    final remoteClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: jsonEncode({
        'schemaVersion': 1,
        'createdAt': 2000,
        'envelopes': [
          KnowledgeSyncEnvelope(
            id: safeHistory.id,
            entityType: KnowledgeSyncEntityType.reviewHistory,
            schemaVersion: 1,
            updatedAt: 2000,
            sourceRefs: safeHistory.sourceRefs,
            payload: safeHistory.toJson(),
          ).toJson(),
          KnowledgeSyncEnvelope(
            id: unsafeHistory.id,
            entityType: KnowledgeSyncEntityType.reviewHistory,
            schemaVersion: 1,
            updatedAt: 2000,
            sourceRefs: unsafeHistory.sourceRefs,
            payload: {
              ...unsafeHistory.toJson(),
              'apiKey': 'must-not-enter-review',
            },
          ).toJson(),
          KnowledgeSyncEnvelope(
            id: untraceableHistory.id,
            entityType: KnowledgeSyncEntityType.reviewHistory,
            schemaVersion: 1,
            updatedAt: 2000,
            payload: untraceableHistory.toJson(),
          ).toJson(),
        ],
      }),
    });

    final first = await service.submitRemoteReviewHistoryToReview(
      client: remoteClient,
    );
    final second = await service.submitRemoteReviewHistoryToReview(
      client: remoteClient,
    );

    expect(first.submittedCount, 1);
    expect(first.skippedCount, 1);
    expect(second.submittedCount, 0);
    expect(second.skippedCount, 2);
    final reviewItems = await reviewStore.list(
      sourceType: ReviewItemSourceType.reviewHistoryImport,
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, safeHistory.id);
    expect(jsonEncode(reviewItems.single.payload), isNot(contains('apiKey')));
    expect(await spacedReviewStore.list(), isEmpty);
  });

  test('remote sync upload is blocked by remote incoming and conflicts',
      () async {
    final localCard = await stageAppliedCard('kc-shared');
    final remoteIncomingCard = card(
      id: 'kc-remote-only',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Remote-only evidence.',
      explanation: 'Remote-only card must not be overwritten.',
      sourceRefs: [
        traceableRef(
          bookId: 9,
          cfi: 'epubcfi(/6/30)',
          snippet: 'Remote-only evidence.',
        ),
      ],
    );
    final incomingBundle = jsonEncode({
      'schemaVersion': 1,
      'createdAt': 2000,
      'envelopes': [
        KnowledgeSyncEnvelope(
          id: remoteIncomingCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 2000,
          sourceRefs: remoteIncomingCard.sourceRefs,
          payload: remoteIncomingCard.toJson(),
        ).toJson(),
      ],
    });
    final incomingClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: incomingBundle,
    });

    await expectLater(
      service.uploadRemoteSyncBundle(client: incomingClient),
      throwsA(
        predicate((Object error) =>
            error is StateError && error.message.contains('remote-incoming')),
      ),
    );
    expect(incomingClient.uploadedPaths, isEmpty);

    final remoteConflictCard = card(
      id: localCard.id,
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Remote changed evidence.',
      explanation: 'Remote changed explanation.',
      sourceRefs: [
        traceableRef(snippet: 'Remote changed evidence.'),
      ],
    );
    final conflictBundle = jsonEncode({
      'schemaVersion': 1,
      'createdAt': 2000,
      'envelopes': [
        KnowledgeSyncEnvelope(
          id: remoteConflictCard.id,
          entityType: KnowledgeSyncEntityType.knowledgeCard,
          schemaVersion: 1,
          updatedAt: 2000,
          sourceRefs: remoteConflictCard.sourceRefs,
          payload: remoteConflictCard.toJson(),
        ).toJson(),
      ],
    });
    final conflictClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: conflictBundle,
    });

    await expectLater(
      service.uploadRemoteSyncBundle(client: conflictClient),
      throwsA(
        predicate((Object error) =>
            error is StateError && error.message.contains('remote-conflict')),
      ),
    );
    expect(conflictClient.uploadedPaths, isEmpty);
  });

  test('remote sync upload is blocked by malformed remote bundles', () async {
    await stageAppliedCard('kc-malformed-upload');
    final malformedClient = _FakeSyncClient({
      KnowledgeAssetExportService.defaultRemoteSyncBundlePath: jsonEncode({
        'schemaVersion': 1,
        'createdAt': 2000,
        'envelopes': ['not-an-envelope'],
      }),
    });

    await expectLater(
      service.uploadRemoteSyncBundle(client: malformedClient),
      throwsA(
        predicate((Object error) =>
            error is StateError &&
            error.message.contains('malformed envelope')),
      ),
    );
    expect(malformedClient.uploadedPaths, isEmpty);
  });

  test('uses safe payload card source refs for applyable sync conflicts',
      () async {
    final conflictCard = card(
      id: 'kc-payload-ref-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      quote: 'Payload carries source refs.',
      sourceRefs: [traceableRef(snippet: 'Payload carries source refs.')],
    );
    final conflict = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      payload: conflictCard.toJson(),
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [conflict.toJson()],
      }),
    );

    await service.submitConflictsToReview();
    final item = (await reviewStore.list(
      sourceType: ReviewItemSourceType.syncConflict,
    ))
        .single;

    expect(item.payload['canApply'], true);
    expect(item.sourceRefs.single.hasBookAnchor, true);
    expect(item.sourceRefs.single.sourceTextSnippet,
        startsWith('Payload carries source refs.'));
  });

  test('submitting sync conflicts to review is idempotent', () async {
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

    final first = await service.submitConflictsToReview();
    final second = await service.submitConflictsToReview();

    expect(first.submittedCount, 1);
    expect(second.submittedCount, 0);
    expect(second.skippedCount, 1);
    expect(
      await reviewStore.list(sourceType: ReviewItemSourceType.syncConflict),
      hasLength(1),
    );
  });

  test('submits sync conflict without source refs with unavailable provenance',
      () async {
    final conflictCard = card(
      id: 'kc-conflict-no-source',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      sourceRefs: const <SourceRef>[],
    );
    final conflict = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'unknown-schema-version',
      payload: conflictCard.toJson(),
    );
    await cardStore.ensureInitialized();
    await cardStore.cardsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'cards': [conflict.toJson()],
      }),
    );

    await service.submitConflictsToReview();
    final item = (await reviewStore.list(
      sourceType: ReviewItemSourceType.syncConflict,
    ))
        .single;

    expect(item.sourceRefs, hasLength(1));
    expect(item.sourceRefs.single.hasUnavailableReason, true);
    expect(
      item.sourceRefs.single.unavailableReason,
      'sync-conflict-no-source',
    );
    expect(item.sourceRefs.single.sourceKind, SourceRefKind.unknown);
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

class _FakeSyncClient extends SyncClientBase {
  _FakeSyncClient(this.files);

  final Map<String, String> files;
  final downloadedPaths = <String>[];
  final uploadedPaths = <String>[];
  final createdDirs = <String>[];
  final safeReadDirs = <String>[];

  @override
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final content = files[remotePath];
    if (content == null) throw StateError('Missing remote path: $remotePath');
    downloadedPaths.add(remotePath);
    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    onProgress?.call(content.length, content.length);
  }

  @override
  String get protocolName => 'fake';

  @override
  Map<String, dynamic> get config => const <String, dynamic>{};

  @override
  bool get isConfigured => true;

  @override
  Future<bool> isExist(String path) async => files.containsKey(path);

  @override
  Future<void> mkdirAll(String path) async {
    createdDirs.add(path);
  }

  @override
  Future<void> ping() async {}

  @override
  Future<List<RemoteFile>> readDir(String path) async => const <RemoteFile>[];

  @override
  Future<RemoteFile?> readProps(String path) async => null;

  @override
  Future<void> remove(String path) async {}

  @override
  Future<List<RemoteFile>> safeReadDir(String path) async {
    safeReadDirs.add(path);
    return const <RemoteFile>[];
  }

  @override
  Future<void> testFullCapabilities() async {}

  @override
  void updateConfig(Map<String, dynamic> newConfig) {}

  @override
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool replace = true,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final content = await File(localPath).readAsString();
    if (!replace && files.containsKey(remotePath)) {
      throw StateError('Remote path already exists: $remotePath');
    }
    files[remotePath] = content;
    uploadedPaths.add(remotePath);
    onProgress?.call(content.length, content.length);
  }
}
