import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

class ConceptGraphIntegrityReport {
  const ConceptGraphIntegrityReport({
    required this.orphanNodeIds,
    required this.brokenEdgeIds,
  });

  final List<String> orphanNodeIds;
  final List<String> brokenEdgeIds;

  bool get hasIssues => orphanNodeIds.isNotEmpty || brokenEdgeIds.isNotEmpty;
}

class ConceptGraphStore {
  ConceptGraphStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get knowledgeDir => Directory(p.join(rootDir.path, '.knowledge'));
  File get graphFile =>
      File(p.join(knowledgeDir.path, 'concept_graph_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    if (!await graphFile.exists()) {
      await graphFile.writeAsString(_encode(const [], const []));
    }
  }

  Future<List<ConceptNode>> listNodes() {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final nodes = List<ConceptNode>.from(graph.nodes);
      nodes.sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
      return nodes;
    });
  }

  Future<List<ConceptEdge>> listEdges() {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final edges = List<ConceptEdge>.from(graph.edges);
      edges.sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
      return edges;
    });
  }

  Future<ConceptNode> upsertNode(ConceptNode node) {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final draftNode = _draftNode(node);
      _replaceOrAddNode(graph.nodes, draftNode);
      await _writeGraphUnlocked(graph.nodes, graph.edges);
      return draftNode;
    });
  }

  Future<ConceptEdge> upsertEdge(ConceptEdge edge) {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final draftEdge = _draftEdge(edge);
      _replaceOrAddEdge(graph.edges, draftEdge);
      await _writeGraphUnlocked(graph.nodes, graph.edges);
      return draftEdge;
    });
  }

  Future<bool> deleteNode(String nodeId) {
    return _enqueue(() async {
      final id = nodeId.trim();
      if (id.isEmpty) return false;
      final graph = await _readGraphUnlocked();
      final beforeNodes = graph.nodes.length;
      graph.nodes.removeWhere((node) => node.id == id);
      final removed = graph.nodes.length != beforeNodes;
      if (removed) {
        graph.edges.removeWhere(
          (edge) => edge.sourceNodeId == id || edge.targetNodeId == id,
        );
        await _writeGraphUnlocked(graph.nodes, graph.edges);
      }
      return removed;
    });
  }

  Future<bool> removeDraftNode(String nodeId) {
    return _enqueue(() async {
      final id = nodeId.trim();
      if (id.isEmpty) return false;
      final graph = await _readGraphUnlocked();
      final index = graph.nodes.indexWhere((node) => node.id == id);
      if (index < 0) return false;
      final node = graph.nodes[index];
      if (node.ownership != AiOutputOwnership.aiGeneratedDraft) return false;
      graph.nodes.removeAt(index);
      graph.edges.removeWhere(
        (edge) => edge.sourceNodeId == id || edge.targetNodeId == id,
      );
      await _writeGraphUnlocked(graph.nodes, graph.edges);
      return true;
    });
  }

  Future<bool> deleteEdge(String edgeId) {
    return _enqueue(() async {
      final id = edgeId.trim();
      if (id.isEmpty) return false;
      final graph = await _readGraphUnlocked();
      final before = graph.edges.length;
      graph.edges.removeWhere((edge) => edge.id == id);
      final removed = graph.edges.length != before;
      if (removed) {
        await _writeGraphUnlocked(graph.nodes, graph.edges);
      }
      return removed;
    });
  }

  Future<ConceptEdge> applyReviewDecision(
    ReviewItem item, {
    int? now,
  }) {
    if (item.sourceType != ReviewItemSourceType.conceptGraphRelation) {
      throw ArgumentError(
        'Review item is not a ConceptGraph relation source: '
        '${item.sourceType.asString}',
      );
    }

    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final index = graph.edges.indexWhere((edge) => edge.id == item.sourceId);
      if (index < 0) {
        throw StateError('ConceptGraph relation not found: ${item.sourceId}');
      }
      final updated = ConceptGraphReviewAdapter.applyReviewDecision(
        graph.edges[index],
        item,
        now: now,
      );
      graph.edges[index] = updated;
      await _writeGraphUnlocked(graph.nodes, graph.edges);
      return updated;
    });
  }

  Future<ConceptDossier?> buildDossier(String nodeId) {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final node = _nodeById(graph.nodes, nodeId);
      if (node == null) return null;

      final relatedEdges = graph.edges
          .where((edge) =>
              edge.sourceNodeId == node.id || edge.targetNodeId == node.id)
          .where((edge) => !edge.isBroken)
          .where((edge) => edge.hasEvidence)
          .toList(growable: false);
      final recommendedNextNodeIds = relatedEdges
          .map((edge) => edge.sourceNodeId == node.id
              ? edge.targetNodeId
              : edge.sourceNodeId)
          .where((id) => id.trim().isNotEmpty)
          .where((id) => _nodeById(graph.nodes, id) != null)
          .toList(growable: false);
      final supportingEvidence = relatedEdges
          .where((edge) => edge.type == ConceptEdgeType.supports)
          .expand((edge) => edge.evidenceRefs)
          .where((ref) => ref.hasEvidence)
          .toList(growable: false);
      final contradictingEvidence = relatedEdges
          .where((edge) => edge.type == ConceptEdgeType.contradicts)
          .expand((edge) => edge.evidenceRefs)
          .where((ref) => ref.hasEvidence)
          .toList(growable: false);

      return ConceptDossier(
        node: node,
        definition: node.summary,
        appearances: node.sourceRefs.where((ref) => ref.hasEvidence).toList(),
        relatedEdges: relatedEdges,
        supportingEvidence: supportingEvidence,
        contradictingEvidence: contradictingEvidence,
        recommendedNextNodeIds: recommendedNextNodeIds,
      );
    });
  }

  Future<ConceptGraphIntegrityReport> inspectIntegrity() {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final nodeIds = graph.nodes.map((node) => node.id).toSet();
      final brokenEdgeIds = graph.edges
          .where((edge) =>
              edge.isBroken ||
              !nodeIds.contains(edge.sourceNodeId) ||
              !nodeIds.contains(edge.targetNodeId))
          .map((edge) => edge.id)
          .toList(growable: false);
      final orphanNodeIds = graph.nodes
          .where((node) => node.isOrphan)
          .map((node) => node.id)
          .toList(growable: false);
      return ConceptGraphIntegrityReport(
        orphanNodeIds: orphanNodeIds,
        brokenEdgeIds: brokenEdgeIds,
      );
    });
  }

  Future<ConceptExplorationPath> exploreFrom(
    String startNodeId, {
    int requestedDepth = 2,
    ConceptExplorationPolicy policy = const ConceptExplorationPolicy(),
  }) {
    return _enqueue(() async {
      final graph = await _readGraphUnlocked();
      final maxDepth = policy.clampDepth(requestedDepth);
      final nodeIds = graph.nodes.map((node) => node.id).toSet();
      if (!nodeIds.contains(startNodeId)) {
        return ConceptExplorationPath(
          startNodeId: startNodeId,
          nodeIds: [startNodeId],
          returnPath: [startNodeId],
          policy: policy,
        );
      }

      final visited = <String>{startNodeId};
      final ordered = <String>[startNodeId];
      var frontier = <String>[startNodeId];
      for (var depth = 0; depth < maxDepth; depth++) {
        final candidates = <String>[];
        final candidateSet = <String>{};
        for (final nodeId in frontier) {
          final neighbors = _neighbors(graph.edges, nodeId)
              .where(nodeIds.contains)
              .where((id) => !visited.contains(id));
          for (final neighbor in neighbors) {
            if (candidateSet.add(neighbor)) {
              candidates.add(neighbor);
            }
          }
        }
        final nextLayer = policy.clampLayer(candidates);
        for (final neighbor in nextLayer) {
          visited.add(neighbor);
          ordered.add(neighbor);
        }
        if (nextLayer.isEmpty) break;
        frontier = nextLayer;
      }

      return ConceptExplorationPath(
        startNodeId: startNodeId,
        nodeIds: ordered,
        returnPath: ordered,
        policy: policy,
      );
    });
  }

  Future<_StoredConceptGraph> _readGraphUnlocked() async {
    await ensureInitialized();
    final raw = await graphFile.readAsString();
    if (raw.trim().isEmpty) return _StoredConceptGraph.empty();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final nodes = (decoded['nodes'] as List?)
                ?.whereType<Map>()
                .map((entry) => ConceptNode.fromJson(
                      Map<String, dynamic>.from(entry.cast<String, dynamic>()),
                    ))
                .toList(growable: true) ??
            <ConceptNode>[];
        final edges = (decoded['edges'] as List?)
                ?.whereType<Map>()
                .map((entry) => ConceptEdge.fromJson(
                      Map<String, dynamic>.from(entry.cast<String, dynamic>()),
                    ))
                .toList(growable: true) ??
            <ConceptEdge>[];
        return _StoredConceptGraph(nodes: nodes, edges: edges);
      }
    } catch (_) {
      // Treat malformed local concept graph state as an empty graph.
    }
    return _StoredConceptGraph.empty();
  }

  Future<void> _writeGraphUnlocked(
    List<ConceptNode> nodes,
    List<ConceptEdge> edges,
  ) async {
    await ensureInitialized();
    await graphFile.writeAsString(_encode(nodes, edges));
  }

  String _encode(List<ConceptNode> nodes, List<ConceptEdge> edges) {
    final payload = <String, dynamic>{
      'version': 1,
      'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
      'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Iterable<String> _neighbors(List<ConceptEdge> edges, String nodeId) sync* {
    for (final edge in edges) {
      if (!edge.hasEvidence || edge.isBroken) continue;
      if (edge.sourceNodeId == nodeId) {
        yield edge.targetNodeId;
      } else if (edge.targetNodeId == nodeId) {
        yield edge.sourceNodeId;
      }
    }
  }

  ConceptNode? _nodeById(List<ConceptNode> nodes, String nodeId) {
    for (final node in nodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  ConceptNode _draftNode(ConceptNode node) {
    return ConceptNode(
      id: node.id,
      type: node.type,
      label: node.label,
      summary: node.summary,
      sourceRefs: node.sourceRefs,
      cardIds: node.cardIds,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: node.createdAt,
      updatedAt: node.updatedAt,
    );
  }

  ConceptEdge _draftEdge(ConceptEdge edge) {
    return ConceptEdge(
      id: edge.id,
      sourceNodeId: edge.sourceNodeId,
      targetNodeId: edge.targetNodeId,
      type: edge.type,
      label: edge.label,
      evidenceRefs: edge.evidenceRefs,
      confidence: edge.confidence,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: edge.createdAt,
      updatedAt: edge.updatedAt,
    );
  }

  void _replaceOrAddNode(List<ConceptNode> nodes, ConceptNode node) {
    final index = nodes.indexWhere((existing) => existing.id == node.id);
    if (index >= 0) {
      nodes[index] = node;
    } else {
      nodes.add(node);
    }
  }

  void _replaceOrAddEdge(List<ConceptEdge> edges, ConceptEdge edge) {
    final index = edges.indexWhere((existing) => existing.id == edge.id);
    if (index >= 0) {
      edges[index] = edge;
    } else {
      edges.add(edge);
    }
  }

  int _sortTimestamp(Object item) {
    return switch (item) {
      ConceptNode node => node.createdAt ?? node.updatedAt ?? 0,
      ConceptEdge edge => edge.createdAt ?? edge.updatedAt ?? 0,
      _ => 0,
    };
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _StoredConceptGraph {
  const _StoredConceptGraph({
    required this.nodes,
    required this.edges,
  });

  factory _StoredConceptGraph.empty() =>
      _StoredConceptGraph(nodes: <ConceptNode>[], edges: <ConceptEdge>[]);

  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
}
