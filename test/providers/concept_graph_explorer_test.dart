import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';

void main() {
  late Directory tempRoot;
  late ConceptGraphStore store;
  late ProviderContainer container;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('concept_graph_page_');
    store = ConceptGraphStore(rootDir: tempRoot);
    container = ProviderContainer(
      overrides: [
        conceptGraphStoreProvider.overrideWithValue(store),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef refFor(String snippet) => SourceRef(
        bookId: 7,
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.reader,
      );

  Future<void> seedGraph() async {
    await store.upsertNode(
      ConceptNode(
        id: 'attention',
        type: ConceptNodeType.concept,
        label: 'Attention',
        summary: 'Selective focus in a reading argument.',
        sourceRefs: [refFor('Attention is selective.')],
        createdAt: 100,
      ),
    );
    await store.upsertNode(
      ConceptNode(
        id: 'memory',
        type: ConceptNodeType.concept,
        label: 'Memory',
        summary: 'Retention after reading.',
        sourceRefs: [refFor('Memory keeps useful distinctions.')],
        createdAt: 90,
      ),
    );
    await store.upsertNode(
      const ConceptNode(
        id: 'orphan',
        type: ConceptNodeType.concept,
        label: 'Orphan',
        createdAt: 80,
      ),
    );
    await store.upsertEdge(
      ConceptEdge(
        id: 'attention-memory',
        sourceNodeId: 'attention',
        targetNodeId: 'memory',
        type: ConceptEdgeType.supports,
        label: 'reinforces',
        evidenceRefs: [refFor('Attention supports memory.')],
        createdAt: 110,
      ),
    );
    await store.upsertEdge(
      ConceptEdge(
        id: 'broken-edge',
        sourceNodeId: 'attention',
        targetNodeId: 'missing',
        type: ConceptEdgeType.relatedTo,
        evidenceRefs: [refFor('This edge points to a missing node.')],
        createdAt: 120,
      ),
    );
  }

  test('refresh loads nodes and integrity report', () async {
    await seedGraph();

    await container.read(conceptGraphExplorerProvider.notifier).refresh();
    final state = container.read(conceptGraphExplorerProvider);

    expect(state.nodes.value!.map((node) => node.label), [
      'Attention',
      'Memory',
      'Orphan',
    ]);
    expect(state.integrity?.orphanNodeIds, ['orphan']);
    expect(state.integrity?.brokenEdgeIds, ['broken-edge']);
  });

  test('selectNode builds dossier and local exploration path', () async {
    await seedGraph();

    final notifier = container.read(conceptGraphExplorerProvider.notifier);
    await notifier.refresh();
    await notifier.selectNode('attention');
    final selection =
        container.read(conceptGraphExplorerProvider).selection.value!;

    expect(selection.dossier.node.label, 'Attention');
    expect(selection.dossier.appearances.single.canJumpBack, true);
    expect(
      selection.dossier.relatedEdges.map((edge) => edge.id),
      contains('attention-memory'),
    );
    expect(selection.path.nodeIds, containsAll(['attention', 'memory']));
  });
}
