import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/derived_book_concept_graph_loader.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/knowledge/rag_evidence_knowledge_card_producer.dart';
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

typedef ConceptGraphLibrarySearch = Future<AiSemanticSearchLibraryResult>
    Function(String query);
typedef ConceptGraphGlobalLayerStatusLoader
    = Future<AiGlobalIndexBookLayerStatus?> Function(int bookId);
typedef ConceptGraphGlobalLayerRebuilder = Future<AiGlobalIndexStats> Function({
  required int bookId,
});
typedef ConceptGraphBookIndexReadinessLoader = Future<AiBookIndexReadiness>
    Function(int bookId);

final conceptGraphStoreProvider = Provider<ConceptGraphStore>((ref) {
  return ConceptGraphStore();
});

final conceptGraphReviewItemStoreProvider = Provider<ReviewItemStore>((ref) {
  return ReviewItemStore();
});

final conceptGraphKnowledgeCardStoreProvider =
    Provider<KnowledgeCardStore>((ref) {
  return KnowledgeCardStore();
});

final conceptGraphProducerProvider = Provider<ConceptGraphProducer>((ref) {
  return ConceptGraphProducer(
    graphStore: ref.watch(conceptGraphStoreProvider),
    reviewStore: ref.watch(conceptGraphReviewItemStoreProvider),
  );
});

final conceptGraphRagCardProducerProvider =
    Provider<RagEvidenceKnowledgeCardProducer>((ref) {
  return RagEvidenceKnowledgeCardProducer(
    cardStore: ref.watch(conceptGraphKnowledgeCardStoreProvider),
    reviewStore: ref.watch(conceptGraphReviewItemStoreProvider),
  );
});

final conceptGraphLibrarySearchProvider =
    Provider<ConceptGraphLibrarySearch>((ref) {
  final service = SemanticSearchLibrary();
  return (query) => service.search(
        query: query,
        maxResults: 6,
        onlyIndexed: true,
        allowQueryEmbedding: false,
        allowVectorFallback: false,
        allowRerank: false,
      );
});

final conceptGraphDerivedBookLoaderProvider =
    Provider<DerivedBookConceptGraphLoader>((ref) {
  return AiGlobalDerivedBookConceptGraphLoader();
});

final conceptGraphDerivedBookCatalogProvider =
    Provider<DerivedBookConceptGraphCatalog>((ref) {
  return AiGlobalDerivedBookConceptGraphCatalog();
});

final conceptGraphGlobalLayerStatusProvider =
    Provider<ConceptGraphGlobalLayerStatusLoader>((ref) {
  final builder = AiGlobalIndexBuilder();
  return builder.getBookLayerStatus;
});

final conceptGraphGlobalLayerRebuilderProvider =
    Provider<ConceptGraphGlobalLayerRebuilder>((ref) {
  final builder = AiGlobalIndexBuilder();
  return ({required int bookId}) => builder.rebuildBook(bookId: bookId);
});

final conceptGraphBookIndexReadinessProvider =
    Provider<ConceptGraphBookIndexReadinessLoader>((ref) {
  final inspector = AiBookIndexReadinessInspector();
  return inspector.inspectBook;
});

final conceptGraphExplorerProvider = StateNotifierProvider<
    ConceptGraphExplorerNotifier, ConceptGraphExplorerState>((ref) {
  return ConceptGraphExplorerNotifier(
    ref.watch(conceptGraphStoreProvider),
    ref.watch(conceptGraphProducerProvider),
    ref.watch(conceptGraphRagCardProducerProvider),
    ref.watch(conceptGraphLibrarySearchProvider),
  );
});

class ConceptGraphExplorerSelection {
  const ConceptGraphExplorerSelection({
    required this.dossier,
    required this.path,
  });

  final ConceptDossier dossier;
  final ConceptExplorationPath path;
}

class ConceptGraphExplorerState {
  const ConceptGraphExplorerState({
    required this.nodes,
    required this.edges,
    required this.selection,
    required this.draftCandidate,
    required this.ragKnowledgeCard,
    this.selectedNodeId,
    this.integrity,
    this.lastError,
  });

  factory ConceptGraphExplorerState.initial() {
    return const ConceptGraphExplorerState(
      nodes: AsyncValue<List<ConceptNode>>.data(<ConceptNode>[]),
      edges: AsyncValue<List<ConceptEdge>>.data(<ConceptEdge>[]),
      selection: AsyncValue<ConceptGraphExplorerSelection?>.data(null),
      draftCandidate: AsyncValue<ConceptGraphProducerResult?>.data(null),
      ragKnowledgeCard:
          AsyncValue<RagEvidenceKnowledgeCardProducerResult?>.data(null),
    );
  }

  final AsyncValue<List<ConceptNode>> nodes;
  final AsyncValue<List<ConceptEdge>> edges;
  final AsyncValue<ConceptGraphExplorerSelection?> selection;
  final AsyncValue<ConceptGraphProducerResult?> draftCandidate;
  final AsyncValue<RagEvidenceKnowledgeCardProducerResult?> ragKnowledgeCard;
  final String? selectedNodeId;
  final ConceptGraphIntegrityReport? integrity;
  final String? lastError;

  bool get isCreatingDraftCandidate => draftCandidate.isLoading;
  bool get isCreatingRagKnowledgeCard => ragKnowledgeCard.isLoading;

  Map<String, ConceptNode> get nodesById {
    return {
      for (final node in nodes.valueOrNull ?? const <ConceptNode>[])
        node.id: node,
    };
  }

  Map<String, ConceptEdge> get edgesById {
    return {
      for (final edge in edges.valueOrNull ?? const <ConceptEdge>[])
        edge.id: edge,
    };
  }

  ConceptGraphExplorerState copyWith({
    AsyncValue<List<ConceptNode>>? nodes,
    AsyncValue<List<ConceptEdge>>? edges,
    AsyncValue<ConceptGraphExplorerSelection?>? selection,
    AsyncValue<ConceptGraphProducerResult?>? draftCandidate,
    AsyncValue<RagEvidenceKnowledgeCardProducerResult?>? ragKnowledgeCard,
    Object? selectedNodeId = _unset,
    ConceptGraphIntegrityReport? integrity,
    String? lastError,
    bool clearError = false,
  }) {
    return ConceptGraphExplorerState(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      selection: selection ?? this.selection,
      draftCandidate: draftCandidate ?? this.draftCandidate,
      ragKnowledgeCard: ragKnowledgeCard ?? this.ragKnowledgeCard,
      selectedNodeId: identical(selectedNodeId, _unset)
          ? this.selectedNodeId
          : selectedNodeId as String?,
      integrity: integrity ?? this.integrity,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class ConceptGraphExplorerNotifier
    extends StateNotifier<ConceptGraphExplorerState> {
  ConceptGraphExplorerNotifier(
    this._store,
    this._producer,
    this._ragCardProducer,
    this._librarySearch,
  ) : super(ConceptGraphExplorerState.initial());

  final ConceptGraphStore _store;
  final ConceptGraphProducer _producer;
  final RagEvidenceKnowledgeCardProducer _ragCardProducer;
  final ConceptGraphLibrarySearch _librarySearch;

  Future<void> refresh() async {
    state = state.copyWith(
      nodes: const AsyncValue<List<ConceptNode>>.loading(),
      edges: const AsyncValue<List<ConceptEdge>>.loading(),
      clearError: true,
    );
    try {
      final nodes = await _store.listNodes();
      final edges = await _store.listEdges();
      final integrity = await _store.inspectIntegrity();
      state = state.copyWith(
        nodes: AsyncValue<List<ConceptNode>>.data(nodes),
        edges: AsyncValue<List<ConceptEdge>>.data(edges),
        integrity: integrity,
        clearError: true,
      );
      final selectedNodeId = state.selectedNodeId;
      if (selectedNodeId != null &&
          nodes.any((node) => node.id == selectedNodeId)) {
        await selectNode(selectedNodeId);
      } else if (nodes.isEmpty) {
        state = state.copyWith(
          selection:
              const AsyncValue<ConceptGraphExplorerSelection?>.data(null),
          selectedNodeId: null,
        );
      }
    } catch (error, stackTrace) {
      state = state.copyWith(
        nodes: AsyncValue<List<ConceptNode>>.error(error, stackTrace),
        edges: AsyncValue<List<ConceptEdge>>.error(error, stackTrace),
        lastError: error.toString(),
      );
    }
  }

  Future<void> selectNode(String nodeId) async {
    state = state.copyWith(
      selection: const AsyncValue<ConceptGraphExplorerSelection?>.loading(),
      selectedNodeId: nodeId,
      clearError: true,
    );
    try {
      final dossier = await _store.buildDossier(nodeId);
      if (dossier == null) {
        state = state.copyWith(
          selection:
              const AsyncValue<ConceptGraphExplorerSelection?>.data(null),
          selectedNodeId: null,
          clearError: true,
        );
        return;
      }
      final path = await _store.exploreFrom(nodeId);
      state = state.copyWith(
        selection: AsyncValue<ConceptGraphExplorerSelection?>.data(
          ConceptGraphExplorerSelection(
            dossier: dossier,
            path: path,
          ),
        ),
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        selection: AsyncValue<ConceptGraphExplorerSelection?>.error(
          error,
          stackTrace,
        ),
        lastError: error.toString(),
      );
    }
  }

  Future<void> createDraftCandidateFromLibrarySearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      draftCandidate: const AsyncValue<ConceptGraphProducerResult?>.loading(),
      clearError: true,
    );
    try {
      final searchResult = await _librarySearch(trimmed);
      final producerResult = await _producer.createFromLibrarySearchResult(
        searchResult,
        createReviewItems: false,
      );
      state = state.copyWith(
        draftCandidate:
            AsyncValue<ConceptGraphProducerResult?>.data(producerResult),
        clearError: true,
      );
      if (producerResult.createdAny) {
        await refresh();
        final firstNodeId = producerResult.nodes
            .map((node) => node.id)
            .firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
        if (firstNodeId.isNotEmpty) {
          await selectNode(firstNodeId);
        }
      }
    } catch (error, stackTrace) {
      state = state.copyWith(
        draftCandidate:
            AsyncValue<ConceptGraphProducerResult?>.error(error, stackTrace),
        lastError: error.toString(),
      );
    }
  }

  Future<void> createKnowledgeCardFromLibrarySearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      ragKnowledgeCard:
          const AsyncValue<RagEvidenceKnowledgeCardProducerResult?>.loading(),
      clearError: true,
    );
    try {
      final searchResult = await _librarySearch(trimmed);
      final result = await _ragCardProducer.createFromLibrarySearchResult(
        searchResult,
        createReviewItem: false,
      );
      state = state.copyWith(
        ragKnowledgeCard:
            AsyncValue<RagEvidenceKnowledgeCardProducerResult?>.data(result),
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        ragKnowledgeCard:
            AsyncValue<RagEvidenceKnowledgeCardProducerResult?>.error(
          error,
          stackTrace,
        ),
        lastError: error.toString(),
      );
    }
  }

  Future<ConceptNode> addDerivedNodePreview(
    ConceptNode node, {
    int? now,
  }) async {
    final nodeId = node.id.trim();
    final label = node.label.trim();
    final sourceRefs =
        node.sourceRefs.where((sourceRef) => sourceRef.hasEvidence).toList();
    if (nodeId.isEmpty || label.isEmpty || sourceRefs.isEmpty) {
      throw StateError(
        'Cannot add a derived concept node without id, label, and evidence.',
      );
    }
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final draft = await _store.upsertNode(
      ConceptNode(
        id: nodeId,
        type: node.type,
        label: label,
        summary: node.summary,
        sourceRefs: sourceRefs,
        cardIds: node.cardIds,
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: node.createdAt ?? timestamp,
        updatedAt: timestamp,
      ),
    );
    await refresh();
    await selectNode(draft.id);
    return draft;
  }

  Future<ConceptNode> mergeDerivedNodePreview(
    ConceptNode derivedNode, {
    required String targetNodeId,
    int? now,
  }) async {
    final targetId = targetNodeId.trim();
    final derivedSourceRefs = derivedNode.sourceRefs
        .where((sourceRef) => sourceRef.hasEvidence)
        .toList(growable: false);
    if (targetId.isEmpty || derivedSourceRefs.isEmpty) {
      throw StateError(
        'Cannot merge a derived concept node without target and evidence.',
      );
    }
    final nodes = await _store.listNodes();
    final target = nodes.firstWhere(
      (node) => node.id == targetId,
      orElse: () => throw StateError('Merge target not found: $targetId'),
    );
    final sourceRefs = _mergeSourceRefs(
      target.sourceRefs.where((sourceRef) => sourceRef.hasEvidence),
      derivedSourceRefs,
    );
    if (sourceRefs.isEmpty) {
      throw StateError('Cannot merge a derived concept node without evidence.');
    }
    final cardIds = <String>{
      ...target.cardIds.where((id) => id.trim().isNotEmpty),
      ...derivedNode.cardIds.where((id) => id.trim().isNotEmpty),
    }.toList(growable: false);
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final merged = await _store.upsertNode(
      ConceptNode(
        id: target.id,
        type: target.type,
        label: target.label,
        summary: _mergeSummary(target.summary, derivedNode.summary),
        sourceRefs: sourceRefs,
        cardIds: cardIds,
        ownership: target.ownership,
        createdAt: target.createdAt ?? timestamp,
        updatedAt: timestamp,
      ),
    );
    await refresh();
    await selectNode(merged.id);
    return merged;
  }

  Future<bool> removeSavedNode(String nodeId) async {
    final id = nodeId.trim();
    if (id.isEmpty) {
      throw StateError('Cannot remove a concept node without id.');
    }
    final removed = await _store.deleteNode(id);
    await refresh();
    return removed;
  }

  Future<ConceptEdge> addDerivedEdgePreview(
    ConceptEdge edge, {
    required ConceptNode sourceNode,
    required ConceptNode targetNode,
    int? now,
  }) {
    return _upsertDerivedEdgePreview(
      edge,
      sourceNode: sourceNode,
      targetNode: targetNode,
      keepExistingRelationShape: true,
      now: now,
    );
  }

  Future<ConceptEdge> saveEditedDerivedEdgePreview(
    ConceptEdge edge, {
    required ConceptNode sourceNode,
    required ConceptNode targetNode,
    required ConceptEdgeType type,
    required String label,
    int? now,
  }) {
    return _upsertDerivedEdgePreview(
      ConceptEdge(
        id: edge.id,
        sourceNodeId: edge.sourceNodeId,
        targetNodeId: edge.targetNodeId,
        type: type,
        label: label.trim().isEmpty ? null : label.trim(),
        evidenceRefs: edge.evidenceRefs,
        confidence: edge.confidence,
        ownership: edge.ownership,
        createdAt: edge.createdAt,
      ),
      sourceNode: sourceNode,
      targetNode: targetNode,
      keepExistingRelationShape: false,
      now: now,
    );
  }

  Future<ConceptEdge> mergeDerivedEdgePreview(
    ConceptEdge derivedEdge, {
    required String targetEdgeId,
    int? now,
  }) async {
    final targetId = targetEdgeId.trim();
    final derivedEvidenceRefs = derivedEdge.evidenceRefs
        .where((sourceRef) => sourceRef.hasEvidence)
        .toList(growable: false);
    if (targetId.isEmpty || derivedEvidenceRefs.isEmpty) {
      throw StateError(
        'Cannot merge a derived concept relation without target and evidence.',
      );
    }
    final edges = await _store.listEdges();
    final target = edges.firstWhere(
      (edge) => edge.id == targetId,
      orElse: () =>
          throw StateError('Merge target relation not found: $targetId'),
    );
    if (!_sameConceptEdgeEndpoints(target, derivedEdge)) {
      throw StateError('Merge target relation endpoints do not match.');
    }
    final evidenceRefs = _mergeSourceRefs(
      target.evidenceRefs.where((sourceRef) => sourceRef.hasEvidence),
      derivedEvidenceRefs,
    );
    if (evidenceRefs.isEmpty) {
      throw StateError(
        'Cannot merge a derived concept relation without evidence.',
      );
    }
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final merged = await _store.upsertEdge(
      ConceptEdge(
        id: target.id,
        sourceNodeId: target.sourceNodeId,
        targetNodeId: target.targetNodeId,
        type: target.type,
        label: target.label,
        evidenceRefs: evidenceRefs,
        confidence: target.confidence ?? derivedEdge.confidence,
        ownership: target.ownership,
        createdAt: target.createdAt ?? timestamp,
        updatedAt: timestamp,
      ),
    );
    await refresh();
    await selectNode(merged.sourceNodeId);
    return merged;
  }

  Future<ConceptEdge> _upsertDerivedEdgePreview(
    ConceptEdge edge, {
    required ConceptNode sourceNode,
    required ConceptNode targetNode,
    required bool keepExistingRelationShape,
    int? now,
  }) async {
    final edgeId = edge.id.trim();
    final sourceId = edge.sourceNodeId.trim();
    final targetId = edge.targetNodeId.trim();
    final evidenceRefs =
        edge.evidenceRefs.where((sourceRef) => sourceRef.hasEvidence).toList();
    if (edgeId.isEmpty ||
        sourceId.isEmpty ||
        targetId.isEmpty ||
        evidenceRefs.isEmpty) {
      throw StateError(
        'Cannot add a derived concept relation without id, endpoints, and evidence.',
      );
    }
    if (sourceNode.id.trim() != sourceId || targetNode.id.trim() != targetId) {
      throw StateError('Derived concept relation endpoints do not match.');
    }

    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final existingNodes = await _store.listNodes();
    final existingNodeIds = existingNodes.map((node) => node.id).toSet();
    if (!existingNodeIds.contains(sourceId)) {
      await _store.upsertNode(
        _draftDerivedEndpointNode(sourceNode, timestamp: timestamp),
      );
    }
    if (!existingNodeIds.contains(targetId)) {
      await _store.upsertNode(
        _draftDerivedEndpointNode(targetNode, timestamp: timestamp),
      );
    }

    final existingEdge = await _findExistingEdge(edgeId);
    final mergedEvidenceRefs = existingEdge == null
        ? evidenceRefs
        : _mergeSourceRefs(
            existingEdge.evidenceRefs
                .where((sourceRef) => sourceRef.hasEvidence),
            evidenceRefs,
          );
    final draftEdge = await _store.upsertEdge(
      ConceptEdge(
        id: edgeId,
        sourceNodeId: sourceId,
        targetNodeId: targetId,
        type: keepExistingRelationShape
            ? existingEdge?.type ?? edge.type
            : edge.type,
        label: keepExistingRelationShape
            ? existingEdge?.label ?? edge.label
            : edge.label,
        evidenceRefs: mergedEvidenceRefs,
        confidence: existingEdge?.confidence ?? edge.confidence,
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: existingEdge?.createdAt ?? edge.createdAt ?? timestamp,
        updatedAt: timestamp,
      ),
    );
    await refresh();
    await selectNode(sourceId);
    return draftEdge;
  }

  Future<bool> removeSavedEdge(String edgeId) async {
    final id = edgeId.trim();
    if (id.isEmpty) {
      throw StateError('Cannot remove a concept relation without id.');
    }
    final removed = await _store.deleteEdge(id);
    await refresh();
    return removed;
  }

  Future<ConceptEdge?> _findExistingEdge(String edgeId) async {
    final edges = await _store.listEdges();
    for (final edge in edges) {
      if (edge.id == edgeId) return edge;
    }
    return null;
  }
}

const Object _unset = Object();

List<SourceRef> _mergeSourceRefs(
  Iterable<SourceRef> primary,
  Iterable<SourceRef> secondary,
) {
  final seen = <String>{};
  final merged = <SourceRef>[];
  for (final sourceRef in [...primary, ...secondary]) {
    final key = _sourceRefMergeKey(sourceRef);
    if (seen.add(key)) merged.add(sourceRef);
  }
  return merged;
}

String _sourceRefMergeKey(SourceRef sourceRef) {
  return [
    sourceRef.sourceKind.asString,
    sourceRef.bookId?.toString() ?? '',
    sourceRef.href ?? '',
    sourceRef.cfi ?? '',
    sourceRef.chunkId?.toString() ?? '',
    sourceRef.jumpLink ?? '',
    sourceRef.sourceHash ?? '',
    sourceRef.sourceTextSnippet ?? '',
  ].join('|');
}

String? _mergeSummary(String? targetSummary, String? derivedSummary) {
  final target = targetSummary?.trim();
  if (target != null && target.isNotEmpty) return target;
  final derived = derivedSummary?.trim();
  if (derived != null && derived.isNotEmpty) return derived;
  return null;
}

bool _sameConceptEdgeEndpoints(ConceptEdge primary, ConceptEdge secondary) {
  final primarySourceId = primary.sourceNodeId.trim();
  final primaryTargetId = primary.targetNodeId.trim();
  final secondarySourceId = secondary.sourceNodeId.trim();
  final secondaryTargetId = secondary.targetNodeId.trim();
  if (primarySourceId.isEmpty ||
      primaryTargetId.isEmpty ||
      secondarySourceId.isEmpty ||
      secondaryTargetId.isEmpty) {
    return false;
  }
  return primarySourceId == secondarySourceId &&
          primaryTargetId == secondaryTargetId ||
      primarySourceId == secondaryTargetId &&
          primaryTargetId == secondarySourceId;
}

ConceptNode _draftDerivedEndpointNode(
  ConceptNode node, {
  required int timestamp,
}) {
  final nodeId = node.id.trim();
  final label = node.label.trim();
  final sourceRefs =
      node.sourceRefs.where((sourceRef) => sourceRef.hasEvidence).toList();
  if (nodeId.isEmpty || label.isEmpty || sourceRefs.isEmpty) {
    throw StateError(
      'Cannot add a derived concept relation endpoint without id, label, and evidence.',
    );
  }
  return ConceptNode(
    id: nodeId,
    type: node.type,
    label: label,
    summary: node.summary,
    sourceRefs: sourceRefs,
    cardIds: node.cardIds,
    ownership: AiOutputOwnership.aiGeneratedDraft,
    createdAt: node.createdAt ?? timestamp,
    updatedAt: timestamp,
  );
}
