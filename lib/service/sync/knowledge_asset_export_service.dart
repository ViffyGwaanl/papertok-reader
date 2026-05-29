import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
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
    required this.snapshot,
  });

  final File file;
  final KnowledgeAssetExportSnapshot snapshot;
}

class KnowledgeAssetExportService {
  KnowledgeAssetExportService({
    Directory? rootDir,
    KnowledgeCardStore? knowledgeCardStore,
    SpacedReviewStore? spacedReviewStore,
    KnowledgeAssetExportClock? now,
  })  : rootDir = rootDir ?? MarkdownMemoryStore().rootDir,
        knowledgeCardStore =
            knowledgeCardStore ?? KnowledgeCardStore(rootDir: rootDir),
        spacedReviewStore =
            spacedReviewStore ?? SpacedReviewStore(rootDir: rootDir),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Directory rootDir;
  final KnowledgeCardStore knowledgeCardStore;
  final SpacedReviewStore spacedReviewStore;
  final KnowledgeAssetExportClock _now;

  Directory get knowledgeDir => Directory(p.join(rootDir.path, '.knowledge'));
  File get manifestFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_manifest_v1.json'));

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
    return KnowledgeAssetExportManifestResult(
      file: manifestFile,
      snapshot: snapshot,
    );
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
}
