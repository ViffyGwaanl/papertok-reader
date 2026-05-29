import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

typedef ConceptGraphProducerClock = int Function();

class ConceptGraphProducerResult {
  const ConceptGraphProducerResult({
    this.nodes = const <ConceptNode>[],
    this.edges = const <ConceptEdge>[],
    this.reviewItems = const <ReviewItem>[],
    this.skippedReason,
  });

  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final List<ReviewItem> reviewItems;
  final String? skippedReason;

  bool get createdAny =>
      nodes.isNotEmpty || edges.isNotEmpty || reviewItems.isNotEmpty;
}

class ConceptGraphProducer {
  ConceptGraphProducer({
    Directory? rootDir,
    ConceptGraphStore? graphStore,
    ReviewItemStore? reviewStore,
    ConceptGraphProducerClock? now,
  })  : graphStore = graphStore ?? ConceptGraphStore(rootDir: rootDir),
        reviewStore = reviewStore ?? ReviewItemStore(rootDir: rootDir),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final ConceptGraphStore graphStore;
  final ReviewItemStore reviewStore;
  final ConceptGraphProducerClock _now;

  Future<ConceptGraphProducerResult> createFromKnowledgeCard(
    KnowledgeCard card,
  ) async {
    if (!card.isUserAsset) {
      return const ConceptGraphProducerResult(
        skippedReason: 'knowledge-card-not-applied',
      );
    }

    final evidenceRefs =
        card.sourceRefs.where((ref) => ref.hasEvidence).toList(growable: false);
    if (evidenceRefs.isEmpty) {
      return const ConceptGraphProducerResult(
        skippedReason: 'missing-traceable-source',
      );
    }
    final conceptLabels = _conceptLabels(card);
    if (conceptLabels.isEmpty) {
      return const ConceptGraphProducerResult(
        skippedReason: 'knowledge-card-has-no-concepts',
      );
    }

    final timestamp = _now();
    final existingNodes = {
      for (final node in await graphStore.listNodes()) node.id: node,
    };
    final existingEdges = {
      for (final edge in await graphStore.listEdges()) edge.id: edge,
    };
    final producedNodes = <ConceptNode>[];
    final producedEdges = <ConceptEdge>[];
    final producedReviewItems = <ReviewItem>[];

    final cardNodeId = _cardNodeId(card.id);
    final cardNode = await _upsertDraftNode(
      existingNodes: existingNodes,
      candidate: ConceptNode(
        id: cardNodeId,
        type: ConceptNodeType.card,
        label: card.title,
        summary: card.explanation,
        sourceRefs: evidenceRefs,
        cardIds: [card.id],
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    producedNodes.add(cardNode);
    existingNodes[cardNode.id] = cardNode;

    for (final label in conceptLabels) {
      final conceptNodeId = _conceptNodeId(label);
      final conceptNode = await _upsertDraftNode(
        existingNodes: existingNodes,
        candidate: ConceptNode(
          id: conceptNodeId,
          type: ConceptNodeType.concept,
          label: label,
          sourceRefs: evidenceRefs,
          cardIds: [card.id],
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      producedNodes.add(conceptNode);
      existingNodes[conceptNode.id] = conceptNode;

      final relation = await _upsertDraftEdge(
        existingEdges: existingEdges,
        candidate: ConceptEdge(
          id: _cardConceptEdgeId(cardId: card.id, conceptNodeId: conceptNodeId),
          sourceNodeId: conceptNodeId,
          targetNodeId: cardNodeId,
          type: ConceptEdgeType.appearsIn,
          label: '$label appears in ${card.title}',
          evidenceRefs: evidenceRefs,
          confidence: 0.7,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      if (relation.isFormal) {
        continue;
      }
      producedEdges.add(relation);
      existingEdges[relation.id] = relation;

      final reviewItem = await _upsertReviewItemForRelation(
        relation,
        now: timestamp,
      );
      if (reviewItem != null) {
        producedReviewItems.add(reviewItem);
      }
    }

    return ConceptGraphProducerResult(
      nodes: producedNodes,
      edges: producedEdges,
      reviewItems: producedReviewItems,
    );
  }

  Future<ConceptNode> _upsertDraftNode({
    required Map<String, ConceptNode> existingNodes,
    required ConceptNode candidate,
  }) async {
    final existing = existingNodes[candidate.id];
    if (existing?.isFormal == true) return existing!;
    final merged = _mergeNode(existing, candidate);
    return graphStore.upsertNode(merged);
  }

  Future<ConceptEdge> _upsertDraftEdge({
    required Map<String, ConceptEdge> existingEdges,
    required ConceptEdge candidate,
  }) async {
    final existing = existingEdges[candidate.id];
    if (existing?.isFormal == true) return existing!;
    final merged = _mergeEdge(existing, candidate);
    return graphStore.upsertEdge(merged);
  }

  Future<ReviewItem?> _upsertReviewItemForRelation(
    ConceptEdge edge, {
    required int now,
  }) async {
    final item = ConceptGraphReviewAdapter.fromRelation(edge, now: now);
    final existing = await reviewStore.getById(item.id);
    if (existing != null &&
        existing.status != ReviewItemStatus.draft &&
        existing.status != ReviewItemStatus.pending) {
      return null;
    }
    return reviewStore.upsert(item);
  }

  ConceptNode _mergeNode(ConceptNode? existing, ConceptNode candidate) {
    if (existing == null) return candidate;
    return ConceptNode(
      id: existing.id,
      type: existing.type == ConceptNodeType.unknown
          ? candidate.type
          : existing.type,
      label: existing.label.trim().isEmpty ? candidate.label : existing.label,
      summary: existing.summary ?? candidate.summary,
      sourceRefs: _mergeSourceRefs(existing.sourceRefs, candidate.sourceRefs),
      cardIds: _mergeStrings(existing.cardIds, candidate.cardIds),
      ownership: existing.ownership,
      createdAt: existing.createdAt ?? candidate.createdAt,
      updatedAt: candidate.updatedAt ?? existing.updatedAt,
    );
  }

  ConceptEdge _mergeEdge(ConceptEdge? existing, ConceptEdge candidate) {
    if (existing == null) return candidate;
    return ConceptEdge(
      id: existing.id,
      sourceNodeId: existing.sourceNodeId,
      targetNodeId: existing.targetNodeId,
      type: existing.type == ConceptEdgeType.unknown
          ? candidate.type
          : existing.type,
      label: existing.label ?? candidate.label,
      evidenceRefs:
          _mergeSourceRefs(existing.evidenceRefs, candidate.evidenceRefs),
      confidence: existing.confidence ?? candidate.confidence,
      ownership: existing.ownership,
      createdAt: existing.createdAt ?? candidate.createdAt,
      updatedAt: candidate.updatedAt ?? existing.updatedAt,
    );
  }

  List<String> _conceptLabels(KnowledgeCard card) {
    final seen = <String>{};
    final labels = <String>[];
    for (final value in card.conceptRefs) {
      final label = value.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      if (seen.add(key)) labels.add(label);
    }
    return labels;
  }

  List<SourceRef> _mergeSourceRefs(
    List<SourceRef> existing,
    List<SourceRef> next,
  ) {
    final byKey = <String, SourceRef>{};
    for (final ref in [...existing, ...next]) {
      byKey[_sourceRefKey(ref)] = ref;
    }
    return byKey.values.toList(growable: false);
  }

  List<String> _mergeStrings(List<String> existing, List<String> next) {
    final values = <String>[];
    final seen = <String>{};
    for (final value in [...existing, ...next]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) values.add(trimmed);
    }
    return values;
  }

  String _sourceRefKey(SourceRef ref) {
    final hash = ref.sourceHash?.trim() ?? '';
    if (hash.isNotEmpty) return 'hash:$hash';
    return [
      ref.bookId?.toString() ?? '',
      ref.href ?? '',
      ref.cfi ?? '',
      ref.jumpLink ?? '',
      ref.unavailableReason ?? '',
    ].join('|');
  }

  String _cardNodeId(String cardId) => 'card:${_stableIdPart(cardId)}';

  String _conceptNodeId(String label) => 'concept:${_stableIdPart(label)}';

  String _cardConceptEdgeId({
    required String cardId,
    required String conceptNodeId,
  }) {
    return 'knowledge-card:${_stableIdPart(cardId)}:$conceptNodeId';
  }

  String _stableIdPart(String value) {
    final trimmed = value.trim();
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final digest = sha1.convert(utf8.encode(trimmed)).toString();
    final shortHash = digest.substring(0, 12);
    if (normalized.isEmpty) return 'u-$shortHash';
    if (_hasNonAscii(trimmed)) return '$normalized-$shortHash';
    return normalized;
  }

  bool _hasNonAscii(String value) {
    return value.codeUnits.any((unit) => unit > 0x7f);
  }
}
