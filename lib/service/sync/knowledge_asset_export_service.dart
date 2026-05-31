import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
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

class KnowledgeRemoteConflictStageResult {
  const KnowledgeRemoteConflictStageResult({
    required this.stagedCount,
    required this.skippedCount,
    required this.snapshot,
    required this.remotePreview,
  });

  final int stagedCount;
  final int skippedCount;
  final KnowledgeAssetExportSnapshot snapshot;
  final KnowledgeRemoteSyncPreview remotePreview;
}

class KnowledgeRemoteIncomingReviewResult {
  const KnowledgeRemoteIncomingReviewResult({
    required this.submittedCount,
    required this.skippedCount,
    required this.snapshot,
    required this.remotePreview,
  });

  final int submittedCount;
  final int skippedCount;
  final KnowledgeAssetExportSnapshot snapshot;
  final KnowledgeRemoteSyncPreview remotePreview;
}

class KnowledgeRemoteReviewHistoryReviewResult {
  const KnowledgeRemoteReviewHistoryReviewResult({
    required this.submittedCount,
    required this.skippedCount,
    required this.snapshot,
    required this.remotePreview,
  });

  final int submittedCount;
  final int skippedCount;
  final KnowledgeAssetExportSnapshot snapshot;
  final KnowledgeRemoteSyncPreview remotePreview;
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

class KnowledgeRemoteSyncUploadResult {
  const KnowledgeRemoteSyncUploadResult({
    required this.snapshot,
    required this.file,
    required this.remotePath,
    required this.uploadedAt,
    required this.createdRemote,
    this.rollbackSnapshotFile,
    this.rollbackRestored = false,
    this.removedPartialRemote = false,
    this.conditionalWriteSupported = true,
    this.remotePreconditionFailed = false,
    this.preview,
  });

  final KnowledgeAssetExportSnapshot snapshot;
  final File file;
  final String remotePath;
  final int uploadedAt;
  final bool createdRemote;
  final File? rollbackSnapshotFile;
  final bool rollbackRestored;
  final bool removedPartialRemote;
  final bool conditionalWriteSupported;
  final bool remotePreconditionFailed;
  final KnowledgeRemoteSyncPreview? preview;

  int get uploadedCount => snapshot.includedCount;
}

class KnowledgeRemoteWritebackResult {
  const KnowledgeRemoteWritebackResult({
    this.rollbackSnapshotFile,
    this.rollbackRestored = false,
    this.removedPartialRemote = false,
    this.conditionalWriteSupported = true,
    this.remotePreconditionFailed = false,
  });

  final File? rollbackSnapshotFile;
  final bool rollbackRestored;
  final bool removedPartialRemote;
  final bool conditionalWriteSupported;
  final bool remotePreconditionFailed;
}

class KnowledgeRemoteWritebackException implements Exception {
  const KnowledgeRemoteWritebackException({
    required this.message,
    required this.remotePath,
    this.rollbackSnapshotPath,
    this.rollbackRestored = false,
    this.removedPartialRemote = false,
    this.conditionalWriteSupported = true,
    this.remotePreconditionFailed = false,
    this.rollbackError,
  });

  final String message;
  final String remotePath;
  final String? rollbackSnapshotPath;
  final bool rollbackRestored;
  final bool removedPartialRemote;
  final bool conditionalWriteSupported;
  final bool remotePreconditionFailed;
  final String? rollbackError;

  @override
  String toString() {
    final details = <String>[
      message,
      'remotePath=$remotePath',
      if (rollbackSnapshotPath != null)
        'rollbackSnapshot=$rollbackSnapshotPath',
      if (rollbackRestored) 'rollbackRestored=true',
      if (removedPartialRemote) 'removedPartialRemote=true',
      if (!conditionalWriteSupported) 'conditionalWriteSupported=false',
      if (remotePreconditionFailed) 'remotePreconditionFailed=true',
      if (rollbackError != null) 'rollbackError=$rollbackError',
    ];
    return details.join('; ');
  }
}

class KnowledgeRemoteWritebackExecutor {
  const KnowledgeRemoteWritebackExecutor({
    required this.client,
    required this.localBundleFile,
    required this.remotePath,
    required this.remoteExists,
    required this.precondition,
    required this.rollbackSnapshotFile,
  });

  final SyncClientBase client;
  final File localBundleFile;
  final String remotePath;
  final bool remoteExists;
  final SyncRemoteWritePrecondition precondition;
  final File? rollbackSnapshotFile;

  Future<KnowledgeRemoteWritebackResult> execute() async {
    if (!client.supportsConditionalWrite) {
      throw KnowledgeRemoteWritebackException(
        message:
            'Remote sync writeback requires conditional upload support. Preview again after using a provider with ETag/CAS support.',
        remotePath: remotePath,
        conditionalWriteSupported: false,
      );
    }

    final remoteDir = p.posix.dirname(remotePath);
    final rollbackFile = rollbackSnapshotFile;
    if (remoteExists && rollbackFile != null) {
      await rollbackFile.parent.create(recursive: true);
      await client.downloadFile(remotePath, rollbackFile.path);
    }

    try {
      await client.mkdirAll(remoteDir);
      await client.uploadFileConditionally(
        localBundleFile.path,
        remotePath,
        precondition: precondition,
      );
      return KnowledgeRemoteWritebackResult(
        rollbackSnapshotFile: rollbackFile,
        conditionalWriteSupported: true,
      );
    } catch (error) {
      if (error is SyncPreconditionFailedException) {
        throw KnowledgeRemoteWritebackException(
          message:
              'Remote sync writeback blocked because the remote bundle changed after preview. Preview remote sync again before uploading.',
          remotePath: remotePath,
          rollbackSnapshotPath: rollbackFile?.path,
          remotePreconditionFailed: true,
        );
      }

      var rollbackRestored = false;
      var removedPartialRemote = false;
      Object? rollbackError;
      try {
        if (remoteExists &&
            rollbackFile != null &&
            await rollbackFile.exists()) {
          await client.uploadFile(
            rollbackFile.path,
            remotePath,
            replace: true,
          );
          rollbackRestored = true;
        } else if (await client.isExist(remotePath)) {
          await client.remove(remotePath);
          removedPartialRemote = true;
        }
      } catch (e) {
        rollbackError = e;
      }

      throw KnowledgeRemoteWritebackException(
        message: 'Remote sync writeback failed: $error',
        remotePath: remotePath,
        rollbackSnapshotPath: rollbackFile?.path,
        rollbackRestored: rollbackRestored,
        removedPartialRemote: removedPartialRemote,
        conditionalWriteSupported: true,
        rollbackError: rollbackError?.toString(),
      );
    }
  }
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
  File get remoteSyncBaselineFile => File(
        p.join(knowledgeDir.path, 'knowledge_sync_remote_baseline_v1.json'),
      );

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

  Future<KnowledgeRemoteConflictStageResult>
      stageRemoteKnowledgeCardConflictsToReview({
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
    var stagedCount = 0;
    var skipped = 0;

    for (final envelope in preview.conflicts) {
      final reviewId = _remoteStagedConflictReviewId(envelope.id);
      if (await reviewStore.getById(reviewId) != null ||
          await knowledgeCardStore.getStagedRemoteSyncConflictById(
                envelope.id,
              ) !=
              null) {
        skipped++;
        continue;
      }
      KnowledgeSyncEnvelope? staged;
      try {
        staged = await knowledgeCardStore.stageRemoteSyncConflict(envelope);
        await reviewStore.upsert(
          _reviewItemForConflict(
            staged,
            excludedReason: null,
            timestamp: timestamp,
            reviewId: reviewId,
            extraPayload: {
              'remoteStaged': true,
              'stagedConflictId': staged.id,
            },
          ),
        );
        stagedCount++;
      } catch (_) {
        if (staged != null) {
          await knowledgeCardStore.removeStagedRemoteSyncConflict(staged.id);
        }
        skipped++;
      }
    }

    return KnowledgeRemoteConflictStageResult(
      stagedCount: stagedCount,
      skippedCount: skipped,
      snapshot: snapshot,
      remotePreview: preview,
    );
  }

  Future<KnowledgeRemoteIncomingReviewResult> submitRemoteIncomingToReview({
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

    for (final envelope in preview.incoming) {
      final candidate = _remoteIncomingCardCandidate(
        envelope,
        timestamp: timestamp,
      );
      if (candidate == null) {
        skipped++;
        continue;
      }

      final reviewId = 'knowledge-card:${candidate.id}';
      if (await reviewStore.getById(reviewId) != null) {
        skipped++;
        continue;
      }

      final staged = await knowledgeCardStore.upsertCandidate(candidate);
      if (!staged.inserted) {
        skipped++;
        continue;
      }

      await reviewStore.upsert(
        KnowledgeCardReviewAdapter.fromKnowledgeCard(
          staged.card,
          now: timestamp,
          status: ReviewItemStatus.pending,
        ),
      );
      submitted++;
    }

    return KnowledgeRemoteIncomingReviewResult(
      submittedCount: submitted,
      skippedCount: skipped,
      snapshot: snapshot,
      remotePreview: preview,
    );
  }

  Future<KnowledgeRemoteReviewHistoryReviewResult>
      submitRemoteReviewHistoryToReview({
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

    for (final envelope in preview.incoming) {
      final item = _remoteReviewHistoryReviewItem(
        envelope,
        timestamp: timestamp,
      );
      if (item == null) {
        skipped++;
        continue;
      }
      if (await reviewStore.getById(item.id) != null ||
          await spacedReviewStore.getById(item.sourceId) != null) {
        skipped++;
        continue;
      }
      await reviewStore.upsert(item);
      submitted++;
    }

    return KnowledgeRemoteReviewHistoryReviewResult(
      submittedCount: submitted,
      skippedCount: skipped,
      snapshot: snapshot,
      remotePreview: preview,
    );
  }

  Future<KnowledgeRemoteSyncUploadResult> uploadRemoteSyncBundle({
    SyncClientBase? client,
    String remotePath = defaultRemoteSyncBundlePath,
  }) async {
    final resolvedClient = _configuredRemoteClient(client);
    final snapshot = await buildSnapshot();
    KnowledgeRemoteSyncPreview? preview;
    final remoteDir = p.posix.dirname(remotePath);
    await resolvedClient.safeReadDir(remoteDir);
    final remoteExists = await resolvedClient.isExist(remotePath);
    late final SyncRemoteWritePrecondition precondition;

    if (remoteExists) {
      final remoteETagBefore = await _remoteETagForWriteGuard(
        resolvedClient,
        remotePath,
      );
      preview = await _previewRemoteSync(
        snapshot: snapshot,
        client: resolvedClient,
        remotePath: remotePath,
      );
      _throwIfRemoteUploadBlocked(preview);
      final remoteETagAfter = await _remoteETagForWriteGuard(
        resolvedClient,
        remotePath,
      );
      if (remoteETagAfter != remoteETagBefore) {
        throw KnowledgeRemoteWritebackException(
          message:
              'Remote sync writeback blocked because the remote bundle changed during preview. Preview remote sync again before uploading.',
          remotePath: remotePath,
          remotePreconditionFailed: true,
        );
      }
      precondition = SyncRemoteWritePrecondition.ifMatch(remoteETagBefore);
    } else {
      precondition = const SyncRemoteWritePrecondition.ifNoneMatch();
    }

    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    await syncBundleFile.writeAsString(_buildSyncBundle(snapshot));
    final writeback = await KnowledgeRemoteWritebackExecutor(
      client: resolvedClient,
      localBundleFile: syncBundleFile,
      remotePath: remotePath,
      remoteExists: remoteExists,
      precondition: precondition,
      rollbackSnapshotFile: remoteExists
          ? File(
              p.join(
                knowledgeDir.path,
                'knowledge_sync_remote_rollback_${_now()}.json',
              ),
            )
          : null,
    ).execute();
    await _writeRemoteSyncBaseline(
      remotePath: remotePath,
      snapshot: snapshot,
    );

    return KnowledgeRemoteSyncUploadResult(
      snapshot: snapshot,
      file: syncBundleFile,
      remotePath: remotePath,
      uploadedAt: _now(),
      createdRemote: !remoteExists,
      rollbackSnapshotFile: writeback.rollbackSnapshotFile,
      rollbackRestored: writeback.rollbackRestored,
      removedPartialRemote: writeback.removedPartialRemote,
      conditionalWriteSupported: writeback.conditionalWriteSupported,
      remotePreconditionFailed: writeback.remotePreconditionFailed,
      preview: preview,
    );
  }

  Future<String> _remoteETagForWriteGuard(
    SyncClientBase client,
    String remotePath,
  ) async {
    if (!client.supportsConditionalWrite) {
      throw KnowledgeRemoteWritebackException(
        message:
            'Remote sync writeback requires ETag/CAS support. This sync provider cannot guarantee concurrent write safety.',
        remotePath: remotePath,
        conditionalWriteSupported: false,
      );
    }
    final props = await client.readProps(remotePath);
    final eTag = props?.eTag?.trim();
    if (eTag == null || eTag.isEmpty) {
      throw KnowledgeRemoteWritebackException(
        message:
            'Remote sync writeback requires a remote ETag. Preview again after using a sync provider that exposes ETag/CAS metadata.',
        remotePath: remotePath,
        conditionalWriteSupported: false,
      );
    }
    return eTag;
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

  void _throwIfRemoteUploadBlocked(KnowledgeRemoteSyncPreview preview) {
    final blockers = <String>[
      if (preview.incomingCount > 0) 'remote-incoming:${preview.incomingCount}',
      if (preview.conflictCount > 0) 'remote-conflict:${preview.conflictCount}',
    ];
    if (blockers.isEmpty) return;
    throw StateError(
      'Remote sync upload blocked: ${blockers.join(', ')}. '
      'Review remote differences before writing the local bundle.',
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
    final baseline = await _readRemoteSyncBaseline(remotePath);
    final local = snapshot.included;
    final mergePlan = KnowledgeRemoteMergePlanner.plan(
      local: local,
      remote: remote,
      base: baseline,
      currentSchemaVersion: currentSyncBundleSchemaVersion,
    );

    return KnowledgeRemoteSyncPreview(
      local: mergePlan.local,
      remote: mergePlan.remote,
      incoming: mergePlan.incoming,
      outgoing: mergePlan.outgoing,
      conflicts: mergePlan.conflicts,
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
      final parsed = <KnowledgeSyncEnvelope>[];
      for (final entry in envelopes) {
        if (entry is! Map) {
          throw StateError(
            'Remote knowledge sync bundle contains a malformed envelope.',
          );
        }
        parsed.add(
          KnowledgeSyncEnvelope.fromJson(Map<String, dynamic>.from(entry)),
        );
      }
      return parsed;
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

  Future<List<KnowledgeSyncEnvelope>> _readRemoteSyncBaseline(
    String remotePath,
  ) async {
    if (!await remoteSyncBaselineFile.exists()) {
      return const <KnowledgeSyncEnvelope>[];
    }
    try {
      final decoded = jsonDecode(await remoteSyncBaselineFile.readAsString());
      if (decoded is! Map || decoded['schemaVersion'] != 1) {
        return const <KnowledgeSyncEnvelope>[];
      }
      final remotes = decoded['remotes'];
      final remoteEntry = remotes is Map ? remotes[remotePath] : null;
      return _parseRemoteSyncBaselineEntry(remoteEntry) ??
          const <KnowledgeSyncEnvelope>[];
    } catch (_) {
      return const <KnowledgeSyncEnvelope>[];
    }
  }

  Future<void> _writeRemoteSyncBaseline({
    required String remotePath,
    required KnowledgeAssetExportSnapshot snapshot,
  }) async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    final existingRemotes = await _readRemoteSyncBaselineRemotes();
    final timestamp = _now();
    final safePlan = KnowledgeSyncPolicy.planDefaultSync(snapshot.included);
    existingRemotes[remotePath] = {
      'schemaVersion': currentSyncBundleSchemaVersion,
      'updatedAt': timestamp,
      'envelopes':
          safePlan.included.map((envelope) => envelope.toJson()).toList(),
    };
    await remoteSyncBaselineFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'updatedAt': timestamp,
        'remotes': existingRemotes,
      }),
    );
  }

  Future<Map<String, dynamic>> _readRemoteSyncBaselineRemotes() async {
    if (!await remoteSyncBaselineFile.exists()) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(await remoteSyncBaselineFile.readAsString());
      if (decoded is! Map || decoded['schemaVersion'] != 1) {
        return <String, dynamic>{};
      }
      final remotes = decoded['remotes'];
      if (remotes is! Map) {
        return <String, dynamic>{};
      }
      final sanitized = <String, dynamic>{};
      for (final entry in remotes.entries) {
        final remotePath = entry.key.toString();
        final baseline = _parseRemoteSyncBaselineEntry(entry.value);
        if (remotePath.trim().isNotEmpty && baseline != null) {
          sanitized[remotePath] = {
            'schemaVersion': currentSyncBundleSchemaVersion,
            'updatedAt': _baselineUpdatedAt(entry.value),
            'envelopes': baseline.map((envelope) => envelope.toJson()).toList(),
          };
        }
      }
      return sanitized;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  List<KnowledgeSyncEnvelope>? _parseRemoteSyncBaselineEntry(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != currentSyncBundleSchemaVersion) {
      return null;
    }
    final rawEnvelopes = value['envelopes'];
    if (rawEnvelopes is! List) {
      return null;
    }
    final envelopes = <KnowledgeSyncEnvelope>[];
    final ids = <String>{};
    for (final entry in rawEnvelopes) {
      if (entry is! Map) {
        return null;
      }
      final envelope =
          KnowledgeSyncEnvelope.fromJson(Map<String, dynamic>.from(entry));
      final id = envelope.id.trim();
      if (id.isEmpty ||
          id != envelope.id ||
          !ids.add(id) ||
          envelope.schemaVersion > currentSyncBundleSchemaVersion ||
          KnowledgeSyncPolicy.exclusionReason(envelope) != null) {
        return null;
      }
      envelopes.add(envelope);
    }
    return envelopes;
  }

  int _baselineUpdatedAt(Object? value) {
    if (value is! Map) {
      return _now();
    }
    final raw = value['updatedAt'];
    return raw is num ? raw.toInt() : _now();
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
    String? reviewId,
    Map<String, dynamic> extraPayload = const <String, dynamic>{},
  }) {
    final conflictReason =
        envelope.conflictReason ?? excludedReason ?? 'pending-conflict-review';
    final safeSourceRefs = _safeSourceRefsForConflict(envelope);
    final canApply = excludedReason == remoteSyncPreviewExcludedReason
        ? false
        : _canResolveConflict(envelope);
    return ReviewItem(
      id: reviewId ?? 'sync-conflict:${envelope.id}',
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
        ...extraPayload,
      },
    );
  }

  String _remoteStagedConflictReviewId(String entityId) {
    return 'sync-conflict-remote-staged:$entityId';
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

  KnowledgeCard? _remoteIncomingCardCandidate(
    KnowledgeSyncEnvelope envelope, {
    required int timestamp,
  }) {
    if (envelope.requiresConflictReview) return null;
    if (envelope.entityType != KnowledgeSyncEntityType.knowledgeCard) {
      return null;
    }
    if (envelope.schemaVersion != 1) return null;
    if (KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
      return null;
    }
    try {
      final card = KnowledgeCard.fromJson(envelope.payload);
      final sourceRefs =
          card.sourceRefs.isNotEmpty ? card.sourceRefs : envelope.sourceRefs;
      final safeSourceRefs = sourceRefs
          .map((ref) => SourceRef.fromJson(ref.toSafeJson()))
          .toList(growable: false);
      if (!safeSourceRefs.any((ref) => ref.hasEvidence)) return null;
      final id = envelope.id.trim().isEmpty ? card.id.trim() : envelope.id;
      if (id.trim().isEmpty) return null;
      return card.copyWith(
        id: id,
        sourceRefs: safeSourceRefs,
        reviewState: KnowledgeCardReviewState.pending,
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: card.createdAt ?? timestamp,
        updatedAt: timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  ReviewItem? _remoteReviewHistoryReviewItem(
    KnowledgeSyncEnvelope envelope, {
    required int timestamp,
  }) {
    if (envelope.requiresConflictReview) return null;
    if (envelope.entityType != KnowledgeSyncEntityType.reviewHistory) {
      return null;
    }
    if (envelope.schemaVersion != 1) return null;
    if (KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
      return null;
    }
    try {
      final remote = SpacedReviewItem.fromJson(envelope.payload);
      final id = envelope.id.trim().isEmpty ? remote.id : envelope.id;
      if (id.trim().isEmpty || remote.cardId.trim().isEmpty) return null;
      final sourceRefs = remote.sourceRefs.isNotEmpty
          ? remote.sourceRefs
          : envelope.sourceRefs;
      final safeSourceRefs = sourceRefs
          .map((ref) => SourceRef.fromJson(ref.toSafeJson()))
          .toList(growable: false);
      if (!safeSourceRefs.any((ref) => ref.hasEvidence)) return null;
      final safeItem = SpacedReviewItem(
        id: id,
        cardId: remote.cardId,
        prompt: remote.prompt,
        answer: remote.answer,
        sourceRefs: safeSourceRefs,
        lastReviewedAt: remote.lastReviewedAt,
        dueAt: remote.dueAt,
        intervalDays: remote.intervalDays,
        lapses: remote.lapses,
        reviewHistory: remote.reviewHistory,
      );
      return ReviewItem(
        id: 'review-history-import:$id',
        sourceType: ReviewItemSourceType.reviewHistoryImport,
        sourceId: id,
        title: 'Remote review history: ${remote.prompt}',
        body: [
          'Card: ${remote.cardId}',
          'History entries: ${remote.reviewHistory.length}',
          'Review this remote practice history before importing.',
        ].join('\n'),
        status: ReviewItemStatus.pending,
        sourceRefs: safeSourceRefs,
        createdAt: timestamp,
        updatedAt: timestamp,
        payload: {
          'entityId': id,
          'entityType': envelope.entityType.asString,
          'schemaVersion': envelope.schemaVersion,
          'updatedAt': envelope.updatedAt,
          'reviewHistoryItem': safeItem.toJson(),
        },
      );
    } catch (_) {
      return null;
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
