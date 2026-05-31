import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/service/sync/sync_client_base.dart';
import 'package:papertok_reader/service/sync/sync_client_factory.dart';
import 'package:path/path.dart' as p;

typedef KnowledgeAssetExportClock = int Function();

class KnowledgeAssetExportSnapshot {
  const KnowledgeAssetExportSnapshot({
    required this.manifest,
    required this.included,
    required this.excluded,
    required this.excludedReasons,
  });

  final KnowledgeExportManifest manifest;
  final List<KnowledgeSyncEnvelope> included;
  final List<KnowledgeSyncEnvelope> excluded;
  final Map<String, String> excludedReasons;

  int get includedCount => included.length;
  int get excludedCount => excluded.length;
  int get conflictCount => excluded
      .where((envelope) =>
          envelope.requiresConflictReview ||
          excludedReasons[envelope.id] == 'pending-conflict-review')
      .length;

  String? excludedReasonFor(String id) => excludedReasons[id];
}

class KnowledgeAssetExportManifestResult {
  const KnowledgeAssetExportManifestResult({
    required this.file,
    this.markdownFile,
    this.htmlReportFile,
    this.ankiFile,
    this.syncBundleFile,
    required this.snapshot,
  });

  final File file;
  final File? markdownFile;
  final File? htmlReportFile;
  final File? ankiFile;
  final File? syncBundleFile;
  final KnowledgeAssetExportSnapshot snapshot;
}

class KnowledgeAssetConflictReviewResult {
  const KnowledgeAssetConflictReviewResult({
    required this.submittedCount,
    required this.skippedCount,
    required this.snapshot,
    this.remotePreview,
  });

  final int submittedCount;
  final int skippedCount;
  final KnowledgeAssetExportSnapshot snapshot;
  final KnowledgeRemoteSyncPreview? remotePreview;
}

class KnowledgeRemoteSyncPreview {
  const KnowledgeRemoteSyncPreview({
    required this.local,
    required this.remote,
    required this.incoming,
    required this.outgoing,
    required this.conflicts,
    required this.remotePath,
  });

  final List<KnowledgeSyncEnvelope> local;
  final List<KnowledgeSyncEnvelope> remote;
  final List<KnowledgeSyncEnvelope> incoming;
  final List<KnowledgeSyncEnvelope> outgoing;
  final List<KnowledgeSyncEnvelope> conflicts;
  final String remotePath;

  int get localCount => local.length;
  int get remoteCount => remote.length;
  int get incomingCount => incoming.length;
  int get outgoingCount => outgoing.length;
  int get conflictCount => conflicts.length;
}

class KnowledgeAssetExportService {
  KnowledgeAssetExportService({
    Directory? rootDir,
    KnowledgeCardStore? knowledgeCardStore,
    ReviewItemStore? reviewStore,
    SpacedReviewStore? spacedReviewStore,
    KnowledgeAssetExportClock? now,
  })  : rootDir = rootDir ?? MarkdownMemoryStore().rootDir,
        knowledgeCardStore =
            knowledgeCardStore ?? KnowledgeCardStore(rootDir: rootDir),
        reviewStore = reviewStore ?? ReviewItemStore(rootDir: rootDir),
        spacedReviewStore =
            spacedReviewStore ?? SpacedReviewStore(rootDir: rootDir),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Directory rootDir;
  final KnowledgeCardStore knowledgeCardStore;
  final ReviewItemStore reviewStore;
  final SpacedReviewStore spacedReviewStore;
  final KnowledgeAssetExportClock _now;
  static const int currentSyncBundleSchemaVersion = 1;
  static const String defaultRemoteSyncBundlePath =
      'paper_reader/.knowledge/knowledge_sync_bundle_v1.json';
  static const String remoteSyncPreviewExcludedReason = 'remote-sync-preview';

  Directory get knowledgeDir => Directory(p.join(rootDir.path, '.knowledge'));
  File get manifestFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_manifest_v1.json'));
  File get markdownFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_v1.md'));
  File get htmlReportFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_study_report.html'));
  File get ankiFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_anki.tsv'));
  File get syncBundleFile =>
      File(p.join(knowledgeDir.path, 'knowledge_sync_bundle_v1.json'));

  Future<KnowledgeAssetExportSnapshot> buildSnapshot({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    final timestamp = _now();
    final envelopes = <KnowledgeSyncEnvelope>[
      ...await _cardEnvelopes(timestamp),
      ...await _reviewHistoryEnvelopes(timestamp),
    ];
    final plan = KnowledgeSyncPolicy.planDefaultSync(envelopes);
    final included = includeDrafts
        ? [
            ...plan.included,
            ...plan.excluded.where(
              (envelope) =>
                  envelope.entityType == KnowledgeSyncEntityType.aiDraft,
            ),
          ]
        : plan.included;
    final includedIds = included.map((envelope) => envelope.id).toList();
    final sourceRefs = included
        .expand((envelope) => envelope.sourceRefs)
        .where((ref) => ref.hasEvidence)
        .toList(growable: false);

    return KnowledgeAssetExportSnapshot(
      manifest: KnowledgeExportManifest(
        id: 'knowledge-export-$timestamp',
        createdAt: timestamp,
        formats: const [
          KnowledgeExportFormat.markdown,
          KnowledgeExportFormat.html,
          KnowledgeExportFormat.anki,
          KnowledgeExportFormat.sourceCitationManifest,
        ],
        entityIds: includedIds,
        includeDrafts: includeDrafts,
        includeFullEvidenceText: includeFullEvidenceText,
        sourceRefs: sourceRefs,
      ),
      included: included,
      excluded: plan.excluded
          .where((envelope) =>
              !includeDrafts ||
              envelope.entityType != KnowledgeSyncEntityType.aiDraft)
          .toList(growable: false),
      excludedReasons: Map<String, String>.from(plan.excludedReasons),
    );
  }

  Future<KnowledgeAssetExportManifestResult> writeManifest({
    bool includeDrafts = false,
    bool includeFullEvidenceText = false,
  }) async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    final snapshot = await buildSnapshot(
      includeDrafts: includeDrafts,
      includeFullEvidenceText: includeFullEvidenceText,
    );
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.manifest.toJson()),
    );
    await markdownFile.writeAsString(_buildMarkdown(snapshot));
    await htmlReportFile.writeAsString(_buildHtmlStudyReport(snapshot));
    await ankiFile.writeAsString(_buildAnkiTsv(snapshot));
    await syncBundleFile.writeAsString(_buildSyncBundle(snapshot));
    return KnowledgeAssetExportManifestResult(
      file: manifestFile,
      markdownFile: markdownFile,
      htmlReportFile: htmlReportFile,
      ankiFile: ankiFile,
      syncBundleFile: syncBundleFile,
      snapshot: snapshot,
    );
  }

  Future<KnowledgeRemoteSyncPreview> previewRemoteSync({
    SyncClientBase? client,
    String remotePath = defaultRemoteSyncBundlePath,
  }) async {
    final snapshot = await buildSnapshot();
    return _previewRemoteSync(
      snapshot: snapshot,
      client: client,
      remotePath: remotePath,
    );
  }

  Future<KnowledgeAssetConflictReviewResult> submitRemoteConflictsToReview({
    SyncClientBase? client,
    String remotePath = defaultRemoteSyncBundlePath,
  }) async {
    final snapshot = await buildSnapshot();
    final preview = await _previewRemoteSync(
      snapshot: snapshot,
      client: client,
      remotePath: remotePath,
    );
    final timestamp = _now();
    var submitted = 0;
    var skipped = 0;

    for (final envelope in preview.conflicts) {
      final item = _reviewItemForConflict(
        envelope,
        excludedReason: remoteSyncPreviewExcludedReason,
        timestamp: timestamp,
      );
      final existing = await reviewStore.getById(item.id);
      if (existing != null) {
        skipped++;
        continue;
      }
      await reviewStore.upsert(item);
      submitted++;
    }

    return KnowledgeAssetConflictReviewResult(
      submittedCount: submitted,
      skippedCount: skipped,
      snapshot: snapshot,
      remotePreview: preview,
    );
  }

  Future<KnowledgeAssetConflictReviewResult> submitConflictsToReview() async {
    final snapshot = await buildSnapshot();
    final timestamp = _now();
    var submitted = 0;
    var skipped = 0;

    for (final envelope in snapshot.excluded.where(_isPendingConflict)) {
      final item = _reviewItemForConflict(
        envelope,
        excludedReason: snapshot.excludedReasonFor(envelope.id),
        timestamp: timestamp,
      );
      final existing = await reviewStore.getById(item.id);
      if (existing != null) {
        skipped++;
        continue;
      }
      await reviewStore.upsert(item);
      submitted++;
    }

    return KnowledgeAssetConflictReviewResult(
      submittedCount: submitted,
      skippedCount: skipped,
      snapshot: snapshot,
    );
  }

  Future<KnowledgeRemoteSyncPreview> _previewRemoteSync({
    required KnowledgeAssetExportSnapshot snapshot,
    required SyncClientBase? client,
    required String remotePath,
  }) async {
    final remote = await _downloadRemoteSyncBundle(
      client: client,
      remotePath: remotePath,
    );
    final local = snapshot.included;
    final localById = {for (final envelope in local) envelope.id: envelope};
    final remoteById = {for (final envelope in remote) envelope.id: envelope};
    final incoming = <KnowledgeSyncEnvelope>[];
    final conflicts = <KnowledgeSyncEnvelope>[];

    for (final remoteEnvelope in remote) {
      final reviewed = _reviewEnvelopeForRemote(
        local: localById[remoteEnvelope.id],
        remote: remoteEnvelope,
      );
      if (reviewed.requiresConflictReview) {
        conflicts.add(reviewed);
      } else if (!localById.containsKey(remoteEnvelope.id)) {
        incoming.add(reviewed);
      }
    }

    final outgoing = local
        .where((localEnvelope) => !remoteById.containsKey(localEnvelope.id))
        .toList(growable: false);

    return KnowledgeRemoteSyncPreview(
      local: List.unmodifiable(local),
      remote: List.unmodifiable(remote),
      incoming: List.unmodifiable(incoming),
      outgoing: List.unmodifiable(outgoing),
      conflicts: List.unmodifiable(conflicts),
      remotePath: remotePath,
    );
  }

  Future<List<KnowledgeSyncEnvelope>> _downloadRemoteSyncBundle({
    required SyncClientBase? client,
    required String remotePath,
  }) async {
    final resolvedClient = _configuredRemoteClient(client);
    final tempDir = await Directory.systemTemp.createTemp(
      'papertok_remote_sync_',
    );
    try {
      final localFile =
          File(p.join(tempDir.path, 'knowledge_sync_bundle.json'));
      await resolvedClient.downloadFile(remotePath, localFile.path);
      final decoded = jsonDecode(await localFile.readAsString());
      if (decoded is! Map) {
        throw StateError('Remote knowledge sync bundle is not a JSON object.');
      }
      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion != currentSyncBundleSchemaVersion) {
        throw StateError(
          'Unsupported remote knowledge sync bundle schema: $schemaVersion.',
        );
      }
      final envelopes = decoded['envelopes'];
      if (envelopes is! List) {
        throw StateError('Remote knowledge sync bundle is missing envelopes.');
      }
      return envelopes
          .whereType<Map>()
          .map((entry) => KnowledgeSyncEnvelope.fromJson(
                Map<String, dynamic>.from(entry),
              ))
          .toList(growable: false);
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup for downloaded remote preview data.
      }
    }
  }

  SyncClientBase _configuredRemoteClient(SyncClientBase? client) {
    if (client != null) return client;
    SyncClientFactory.initializeCurrentClient();
    final current = SyncClientFactory.currentClient;
    if (current == null || !current.isConfigured) {
      throw StateError(
        'Knowledge remote sync preview requires a configured sync client.',
      );
    }
    return current;
  }

  KnowledgeSyncEnvelope _reviewEnvelopeForRemote({
    required KnowledgeSyncEnvelope? local,
    required KnowledgeSyncEnvelope remote,
  }) {
    final safetyReason = _remoteSafetyReviewReason(remote);
    if (safetyReason != null) {
      return KnowledgeSyncEnvelope(
        id: remote.id,
        entityType: remote.entityType,
        schemaVersion: remote.schemaVersion,
        updatedAt: remote.updatedAt,
        deletedAt: remote.deletedAt,
        sourceRefs: remote.sourceRefs,
        conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
        conflictReason: safetyReason,
        payload: remote.payload,
      );
    }
    return KnowledgeSyncConflictDetector.reviewEnvelopeFor(
      local: local,
      remote: remote,
      currentSchemaVersion: currentSyncBundleSchemaVersion,
    );
  }

  String? _remoteSafetyReviewReason(KnowledgeSyncEnvelope remote) {
    if (KnowledgeSyncPolicy.containsSecretPayload(remote.payload)) {
      return 'contains-secret';
    }
    if (!remote.shouldSyncByDefault) {
      return 'not-default-sync-entity';
    }
    return null;
  }

  Future<List<KnowledgeSyncEnvelope>> _cardEnvelopes(int fallbackNow) async {
    final envelopes = await knowledgeCardStore.listSyncEnvelopes();
    return envelopes.map((envelope) {
      if (envelope.requiresConflictReview) {
        return envelope;
      }
      final card = KnowledgeCard.fromJson(envelope.payload);
      final updatedAt = card.updatedAt ?? card.createdAt ?? fallbackNow;
      return KnowledgeSyncEnvelope(
        id: card.id,
        entityType: card.isUserAsset
            ? KnowledgeSyncEntityType.knowledgeCard
            : KnowledgeSyncEntityType.aiDraft,
        schemaVersion: 1,
        updatedAt: updatedAt,
        sourceRefs: card.sourceRefs,
        payload: card.toJson(),
      );
    }).toList(growable: false);
  }

  Future<List<KnowledgeSyncEnvelope>> _reviewHistoryEnvelopes(
    int fallbackNow,
  ) async {
    final items = await spacedReviewStore.list();
    return items.map((item) {
      final updatedAt = item.lastReviewedAt ?? item.dueAt ?? fallbackNow;
      return KnowledgeSyncEnvelope(
        id: item.id,
        entityType: KnowledgeSyncEntityType.reviewHistory,
        schemaVersion: 1,
        updatedAt: updatedAt,
        sourceRefs: item.sourceRefs,
        payload: item.toJson(),
      );
    }).toList(growable: false);
  }

  bool _isPendingConflict(KnowledgeSyncEnvelope envelope) {
    return envelope.requiresConflictReview ||
        KnowledgeSyncPolicy.exclusionReason(envelope) ==
            'pending-conflict-review';
  }

  ReviewItem _reviewItemForConflict(
    KnowledgeSyncEnvelope envelope, {
    required String? excludedReason,
    required int timestamp,
  }) {
    final conflictReason =
        envelope.conflictReason ?? excludedReason ?? 'pending-conflict-review';
    final safeSourceRefs = _safeSourceRefsForConflict(envelope);
    final canApply = excludedReason == remoteSyncPreviewExcludedReason
        ? false
        : _canResolveConflict(envelope);
    return ReviewItem(
      id: 'sync-conflict:${envelope.id}',
      sourceType: ReviewItemSourceType.syncConflict,
      sourceId: envelope.id,
      title: 'Sync conflict: ${envelope.id}',
      body: [
        'Entity type: ${envelope.entityType.asString}',
        'Conflict reason: $conflictReason',
        'Excluded from export until reviewed.',
      ].join('\n'),
      status: ReviewItemStatus.pending,
      sourceRefs: safeSourceRefs,
      createdAt: timestamp,
      updatedAt: timestamp,
      payload: {
        'entityId': envelope.id,
        'entityType': envelope.entityType.asString,
        'schemaVersion': envelope.schemaVersion,
        'updatedAt': envelope.updatedAt,
        if (envelope.deletedAt != null) 'deletedAt': envelope.deletedAt,
        'conflictStatus': envelope.conflictStatus.asString,
        'conflictReason': conflictReason,
        'canApply': canApply,
        if (excludedReason == remoteSyncPreviewExcludedReason)
          'remotePreviewOnly': true,
        if (excludedReason != null) 'excludedReason': excludedReason,
        'payloadKeys': envelope.payload.keys
            .map((key) => key.toString())
            .toList(growable: false)
          ..sort(),
        'sourceRefCount': safeSourceRefs.length,
      },
    );
  }

  bool _canResolveConflict(KnowledgeSyncEnvelope envelope) {
    if (!envelope.requiresConflictReview) return false;
    if (envelope.entityType != KnowledgeSyncEntityType.knowledgeCard) {
      return false;
    }
    if (envelope.schemaVersion != 1) return false;
    if (KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
      return false;
    }
    try {
      final refs = _candidateSourceRefsForConflict(envelope);
      return refs.any((ref) => ref.hasBookAnchor || ref.canJumpBack);
    } catch (_) {
      return false;
    }
  }

  List<SourceRef> _safeSourceRefsForConflict(KnowledgeSyncEnvelope envelope) {
    final refs = _candidateSourceRefsForConflict(envelope)
        .map((ref) => SourceRef.fromJson(ref.toSafeJson()))
        .toList(growable: false);
    if (refs.isNotEmpty) return refs;
    return [
      SourceRef(
        sourceKind: SourceRefKind.unknown,
        unavailableReason: 'sync-conflict-no-source',
        createdAt: envelope.updatedAt,
      ),
    ];
  }

  List<SourceRef> _candidateSourceRefsForConflict(
    KnowledgeSyncEnvelope envelope,
  ) {
    if (!KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
      try {
        final card = KnowledgeCard.fromJson(envelope.payload);
        if (card.sourceRefs.isNotEmpty) return card.sourceRefs;
      } catch (_) {
        // Fall back to envelope-level source refs for malformed payloads.
      }
    }
    return envelope.sourceRefs;
  }

  String _buildMarkdown(KnowledgeAssetExportSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('# PaperTok Knowledge Export')
      ..writeln()
      ..writeln('- Export id: ${snapshot.manifest.id}')
      ..writeln('- Created at: ${snapshot.manifest.createdAt}')
      ..writeln('- Included assets: ${snapshot.includedCount}')
      ..writeln('- Held out assets: ${snapshot.excludedCount}')
      ..writeln();

    final knowledgeCards = snapshot.included.where(
      (envelope) =>
          envelope.entityType == KnowledgeSyncEntityType.knowledgeCard,
    );
    final reviewHistory = snapshot.included.where(
      (envelope) =>
          envelope.entityType == KnowledgeSyncEntityType.reviewHistory,
    );

    if (knowledgeCards.isNotEmpty) {
      buffer
        ..writeln('## Knowledge Cards')
        ..writeln();
      for (final envelope in knowledgeCards) {
        final card = KnowledgeCard.fromJson(envelope.payload);
        _writeCard(buffer, card);
      }
    }

    if (reviewHistory.isNotEmpty) {
      buffer
        ..writeln('## Review History')
        ..writeln();
      for (final envelope in reviewHistory) {
        final item = SpacedReviewItem.fromJson(envelope.payload);
        _writeReviewHistory(buffer, item);
      }
    }

    return buffer.toString();
  }

  String _buildSyncBundle(KnowledgeAssetExportSnapshot snapshot) {
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': currentSyncBundleSchemaVersion,
      'createdAt': snapshot.manifest.createdAt,
      'envelopes': snapshot.included
          .map((envelope) => envelope.toJson())
          .toList(growable: false),
    });
  }

  String _buildHtmlStudyReport(KnowledgeAssetExportSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en">')
      ..writeln('<head>')
      ..writeln('  <meta charset="utf-8">')
      ..writeln(
        '  <meta name="viewport" content="width=device-width, initial-scale=1">',
      )
      ..writeln('  <title>PaperTok Knowledge Study Report</title>')
      ..writeln('  <style>')
      ..writeln(
        '    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:0;background:#f7f7f4;color:#1d1d1b;line-height:1.55;}',
      )
      ..writeln(
        '    main{max-width:920px;margin:0 auto;padding:32px 20px 48px;}',
      )
      ..writeln('    h1,h2,h3{line-height:1.2;margin:0 0 12px;}')
      ..writeln(
        '    .summary{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0 24px;}',
      )
      ..writeln(
        '    .chip{border:1px solid #d7d5ce;border-radius:6px;padding:6px 10px;background:#fff;}',
      )
      ..writeln(
        '    article{background:#fff;border:1px solid #dedbd3;border-radius:8px;padding:18px;margin:14px 0;}',
      )
      ..writeln(
        '    blockquote{border-left:3px solid #4f7f69;margin:12px 0;padding-left:12px;color:#363f38;}',
      )
      ..writeln(
          '    .sources{margin-top:14px;padding-top:12px;border-top:1px solid #eee;}')
      ..writeln('    .source{margin:10px 0;}')
      ..writeln('    .muted{color:#686862;}')
      ..writeln('  </style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('<main>')
      ..writeln('  <h1>PaperTok Knowledge Study Report</h1>')
      ..writeln(
          '  <p class="muted">Export id: ${_htmlText(snapshot.manifest.id)}</p>')
      ..writeln('  <section class="summary">')
      ..writeln(
        '    <span class="chip">Included assets: ${snapshot.includedCount}</span>',
      )
      ..writeln(
        '    <span class="chip">Held out assets: ${snapshot.excludedCount}</span>',
      )
      ..writeln(
        '    <span class="chip">Conflicts: ${snapshot.conflictCount}</span>',
      )
      ..writeln('  </section>');

    final knowledgeCards = snapshot.included.where(
      (envelope) =>
          envelope.entityType == KnowledgeSyncEntityType.knowledgeCard,
    );
    final reviewHistory = snapshot.included.where(
      (envelope) =>
          envelope.entityType == KnowledgeSyncEntityType.reviewHistory,
    );

    if (knowledgeCards.isNotEmpty) {
      buffer.writeln('  <section>');
      buffer.writeln('    <h2>Knowledge Cards</h2>');
      for (final envelope in knowledgeCards) {
        final card = KnowledgeCard.fromJson(envelope.payload);
        _writeHtmlCard(buffer, card);
      }
      buffer.writeln('  </section>');
    }

    if (reviewHistory.isNotEmpty) {
      buffer.writeln('  <section>');
      buffer.writeln('    <h2>Review History</h2>');
      for (final envelope in reviewHistory) {
        final item = SpacedReviewItem.fromJson(envelope.payload);
        _writeHtmlReviewHistory(buffer, item);
      }
      buffer.writeln('  </section>');
    }

    buffer
      ..writeln('</main>')
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  String _buildAnkiTsv(KnowledgeAssetExportSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('#separator:tab')
      ..writeln('#html:true')
      ..writeln('Front\tBack\tSource');

    for (final envelope in snapshot.included) {
      switch (envelope.entityType) {
        case KnowledgeSyncEntityType.knowledgeCard:
          final card = KnowledgeCard.fromJson(envelope.payload);
          _writeAnkiRow(
            buffer,
            front: card.title,
            back: [
              card.quote,
              card.explanation,
              if ((card.userNote ?? '').trim().isNotEmpty) card.userNote!,
              if (card.conceptRefs.isNotEmpty)
                'Concepts: ${card.conceptRefs.join(', ')}',
            ].join('\n\n'),
            sourceRefs: card.sourceRefs,
          );
        case KnowledgeSyncEntityType.reviewHistory:
          final item = SpacedReviewItem.fromJson(envelope.payload);
          _writeAnkiRow(
            buffer,
            front: item.prompt,
            back: item.answer,
            sourceRefs: item.sourceRefs,
          );
        case KnowledgeSyncEntityType.reviewItem:
        case KnowledgeSyncEntityType.aiDraft:
        case KnowledgeSyncEntityType.derivedIndex:
        case KnowledgeSyncEntityType.secret:
        case KnowledgeSyncEntityType.unknown:
          break;
      }
    }

    return buffer.toString();
  }

  void _writeAnkiRow(
    StringBuffer buffer, {
    required String front,
    required String back,
    required List<SourceRef> sourceRefs,
  }) {
    final normalizedFront = _paragraph(front);
    final normalizedBack = _paragraph(back);
    if (normalizedFront.isEmpty || normalizedBack.isEmpty) return;

    buffer
      ..write(_ankiField(normalizedFront))
      ..write('\t')
      ..write(_ankiField(normalizedBack))
      ..write('\t')
      ..writeln(_ankiField(_sourceSummary(sourceRefs)));
  }

  void _writeHtmlCard(StringBuffer buffer, KnowledgeCard card) {
    buffer
      ..writeln('    <article>')
      ..writeln('      <h3>${_htmlText(card.title)}</h3>')
      ..writeln(
          '      <p class="muted">Origin: ${_htmlText(card.origin.asString)}</p>')
      ..writeln('      <blockquote>${_htmlText(card.quote)}</blockquote>')
      ..writeln('      <p>${_htmlText(card.explanation)}</p>');
    if ((card.userNote ?? '').trim().isNotEmpty) {
      buffer.writeln(
          '      <p><strong>User note:</strong> ${_htmlText(card.userNote!)}</p>');
    }
    if (card.conceptRefs.isNotEmpty) {
      buffer.writeln(
        '      <p><strong>Concepts:</strong> ${card.conceptRefs.map(_htmlText).join(', ')}</p>',
      );
    }
    _writeHtmlSources(buffer, card.sourceRefs);
    buffer.writeln('    </article>');
  }

  void _writeHtmlReviewHistory(StringBuffer buffer, SpacedReviewItem item) {
    buffer
      ..writeln('    <article>')
      ..writeln('      <h3>${_htmlText(item.prompt)}</h3>')
      ..writeln('      <p>${_htmlText(item.answer)}</p>')
      ..writeln(
        '      <p class="muted">History entries: ${item.reviewHistory.length}</p>',
      );
    _writeHtmlSources(buffer, item.sourceRefs);
    buffer.writeln('    </article>');
  }

  void _writeHtmlSources(StringBuffer buffer, List<SourceRef> refs) {
    final evidenceRefs = refs.where((ref) => ref.hasEvidence).toList();
    if (evidenceRefs.isEmpty) return;
    buffer.writeln('      <section class="sources">');
    buffer.writeln('        <h4>Sources</h4>');
    for (var i = 0; i < evidenceRefs.length; i++) {
      final ref = evidenceRefs[i];
      final label = [
        ref.sourceTitle,
        ref.locationLabel,
        ref.sourceKind.asString,
      ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
      buffer.writeln('        <div class="source">');
      buffer.writeln(
        '          <strong>${i + 1}. ${_htmlText(label.isEmpty ? 'Source' : label)}</strong>',
      );
      if (ref.canJumpBack && (ref.jumpLink ?? '').trim().isNotEmpty) {
        final link = ref.jumpLink!.trim();
        buffer.writeln(
          '          <div><a href="${_htmlAttribute(link)}">${_htmlText(link)}</a></div>',
        );
      }
      if ((ref.sourceTextSnippet ?? '').trim().isNotEmpty) {
        buffer.writeln(
          '          <blockquote>${_htmlText(ref.sourceTextSnippet!)}</blockquote>',
        );
      }
      if ((ref.unavailableReason ?? '').trim().isNotEmpty) {
        buffer.writeln(
          '          <p class="muted">Status: ${_htmlText(ref.unavailableReason!)}</p>',
        );
      }
      buffer.writeln('        </div>');
    }
    buffer.writeln('      </section>');
  }

  void _writeCard(StringBuffer buffer, KnowledgeCard card) {
    buffer
      ..writeln('## ${_heading(card.title)}')
      ..writeln()
      ..writeln('Origin: ${card.origin.asString}')
      ..writeln()
      ..writeln('Quote:')
      ..writeln(_blockquote(card.quote))
      ..writeln()
      ..writeln('Explanation:')
      ..writeln(_paragraph(card.explanation));

    if ((card.userNote ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('User note:')
        ..writeln(_paragraph(card.userNote!));
    }
    if (card.conceptRefs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Concepts: ${card.conceptRefs.map(_inline).join(', ')}');
    }
    _writeSources(buffer, card.sourceRefs);
    buffer.writeln();
  }

  void _writeReviewHistory(StringBuffer buffer, SpacedReviewItem item) {
    buffer
      ..writeln('### ${_heading(item.prompt)}')
      ..writeln()
      ..writeln('Answer:')
      ..writeln(_paragraph(item.answer))
      ..writeln()
      ..writeln('History entries: ${item.reviewHistory.length}');
    _writeSources(buffer, item.sourceRefs);
    buffer.writeln();
  }

  void _writeSources(StringBuffer buffer, List<SourceRef> refs) {
    final evidenceRefs = refs.where((ref) => ref.hasEvidence).toList();
    if (evidenceRefs.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('Sources:');
    for (var i = 0; i < evidenceRefs.length; i++) {
      final ref = evidenceRefs[i];
      final label = [
        ref.sourceTitle,
        ref.locationLabel,
        ref.sourceKind.asString,
      ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
      buffer.writeln('${i + 1}. ${_inline(label.isEmpty ? 'Source' : label)}');
      if ((ref.jumpLink ?? '').trim().isNotEmpty) {
        buffer.writeln('   - Link: ${ref.jumpLink!.trim()}');
      }
      if ((ref.sourceTextSnippet ?? '').trim().isNotEmpty) {
        buffer.writeln('   - Snippet: ${_inline(ref.sourceTextSnippet!)}');
      }
      if ((ref.unavailableReason ?? '').trim().isNotEmpty) {
        buffer.writeln('   - Status: ${_inline(ref.unavailableReason!)}');
      }
    }
  }

  String _sourceSummary(List<SourceRef> refs) {
    final evidenceRefs = refs.where((ref) => ref.hasEvidence).toList();
    if (evidenceRefs.isEmpty) return '';
    return evidenceRefs.map((ref) {
      final parts = <String>[
        [
          ref.sourceTitle,
          ref.locationLabel,
          ref.sourceKind.asString,
        ]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .join(' · '),
        if ((ref.jumpLink ?? '').trim().isNotEmpty) ref.jumpLink!.trim(),
        if ((ref.sourceTextSnippet ?? '').trim().isNotEmpty)
          ref.sourceTextSnippet!.trim(),
        if ((ref.unavailableReason ?? '').trim().isNotEmpty)
          ref.unavailableReason!.trim(),
      ].where((part) => part.trim().isNotEmpty).toList(growable: false);
      return parts.join('\n');
    }).join('\n\n');
  }

  String _heading(String value) {
    final normalized = _paragraph(value).replaceAll('\n', ' ').trim();
    return normalized.isEmpty ? 'Untitled' : normalized.replaceAll('#', r'\#');
  }

  String _paragraph(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  String _blockquote(String value) {
    final paragraph = _paragraph(value);
    if (paragraph.isEmpty) return '>';
    return paragraph.split('\n').map((line) => '> $line').join('\n');
  }

  String _inline(String value) {
    return _paragraph(value).replaceAll('\n', ' ').trim();
  }

  String _ankiField(String value) {
    final normalized = _paragraph(value)
        .replaceAll('\t', ' ')
        .split('\n')
        .map((line) => _htmlEscape(line.trim()))
        .where((line) => line.isNotEmpty)
        .join('<br>');
    return normalized;
  }

  String _htmlText(String value) {
    return _paragraph(value)
        .split('\n')
        .map((line) => _htmlEscape(line.trim()))
        .where((line) => line.isNotEmpty)
        .join('<br>');
  }

  String _htmlAttribute(String value) {
    return _htmlEscape(value).replaceAll('"', '&quot;');
  }

  String _htmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
