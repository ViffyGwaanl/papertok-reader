import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
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
    this.markdownFile,
    this.ankiFile,
    required this.snapshot,
  });

  final File file;
  final File? markdownFile;
  final File? ankiFile;
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
  File get markdownFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_v1.md'));
  File get ankiFile =>
      File(p.join(knowledgeDir.path, 'knowledge_export_anki.tsv'));

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
    await ankiFile.writeAsString(_buildAnkiTsv(snapshot));
    return KnowledgeAssetExportManifestResult(
      file: manifestFile,
      markdownFile: markdownFile,
      ankiFile: ankiFile,
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

  String _htmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
