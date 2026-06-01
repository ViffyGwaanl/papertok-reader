import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/derived_book_concept_graph_loader.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/knowledge/rag_evidence_knowledge_card_producer.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

typedef ConceptGraphLibrarySearch = Future<AiSemanticSearchLibraryResult>
    Function(String query);

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
      selection: AsyncValue<ConceptGraphExplorerSelection?>.data(null),
      draftCandidate: AsyncValue<ConceptGraphProducerResult?>.data(null),
      ragKnowledgeCard:
          AsyncValue<RagEvidenceKnowledgeCardProducerResult?>.data(null),
    );
  }

  final AsyncValue<List<ConceptNode>> nodes;
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

  ConceptGraphExplorerState copyWith({
    AsyncValue<List<ConceptNode>>? nodes,
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
      clearError: true,
    );
    try {
      final nodes = await _store.listNodes();
      final integrity = await _store.inspectIntegrity();
      state = state.copyWith(
        nodes: AsyncValue<List<ConceptNode>>.data(nodes),
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
      final producerResult =
          await _producer.createFromLibrarySearchResult(searchResult);
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
      final result =
          await _ragCardProducer.createFromLibrarySearchResult(searchResult);
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
}

const Object _unset = Object();
