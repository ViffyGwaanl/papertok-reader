import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';

final conceptGraphStoreProvider = Provider<ConceptGraphStore>((ref) {
  return ConceptGraphStore();
});

final conceptGraphExplorerProvider = StateNotifierProvider<
    ConceptGraphExplorerNotifier, ConceptGraphExplorerState>((ref) {
  return ConceptGraphExplorerNotifier(ref.watch(conceptGraphStoreProvider));
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
    this.selectedNodeId,
    this.integrity,
    this.lastError,
  });

  factory ConceptGraphExplorerState.initial() {
    return const ConceptGraphExplorerState(
      nodes: AsyncValue<List<ConceptNode>>.data(<ConceptNode>[]),
      selection: AsyncValue<ConceptGraphExplorerSelection?>.data(null),
    );
  }

  final AsyncValue<List<ConceptNode>> nodes;
  final AsyncValue<ConceptGraphExplorerSelection?> selection;
  final String? selectedNodeId;
  final ConceptGraphIntegrityReport? integrity;
  final String? lastError;

  Map<String, ConceptNode> get nodesById {
    return {
      for (final node in nodes.valueOrNull ?? const <ConceptNode>[])
        node.id: node,
    };
  }

  ConceptGraphExplorerState copyWith({
    AsyncValue<List<ConceptNode>>? nodes,
    AsyncValue<ConceptGraphExplorerSelection?>? selection,
    Object? selectedNodeId = _unset,
    ConceptGraphIntegrityReport? integrity,
    String? lastError,
    bool clearError = false,
  }) {
    return ConceptGraphExplorerState(
      nodes: nodes ?? this.nodes,
      selection: selection ?? this.selection,
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
  ConceptGraphExplorerNotifier(this._store)
      : super(ConceptGraphExplorerState.initial());

  final ConceptGraphStore _store;

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
}

const Object _unset = Object();
