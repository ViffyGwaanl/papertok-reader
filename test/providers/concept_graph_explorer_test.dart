import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late ConceptGraphStore store;
  late ReviewItemStore reviewStore;
  late ProviderContainer container;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('concept_graph_page_');
    store = ConceptGraphStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    container = ProviderContainer(
      overrides: [
        conceptGraphStoreProvider.overrideWithValue(store),
        conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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

  SourceRef libraryRagRef() => SourceRef(
        bookId: 7,
        href: 'Text/rag.xhtml',
        chunkId: 77,
        jumpLink: 'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
        sourceTitle: 'Graph Notes',
        locationLabel: 'Chunk 77',
        sourceTextSnippet: 'Book chunk evidence for attention and memory.',
        sourceKind: SourceRefKind.libraryRag,
      );

  AiSemanticSearchLibraryResult derivedSearchResult(String query) =>
      AiSemanticSearchLibraryResult(
        ok: true,
        query: query,
        evidence: [
          AiSemanticSearchLibraryEvidence(
            chunkId: 77,
            bookId: 7,
            bookTitle: 'Graph Notes',
            href: 'Text/rag.xhtml',
            anchor: 'Chunk 77',
            snippet: 'Book chunk evidence for attention and memory.',
            jumpLink: 'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
            score: 0.91,
            sourceRef: libraryRagRef(),
            derivedLayer: 'graph',
            derivedSummary:
                'GraphRAG community: Key themes: Attention, Memory. Evidence.',
          ),
        ],
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

  test('create draft candidate from derived library RAG result', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        conceptGraphStoreProvider.overrideWithValue(store),
        conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
        conceptGraphLibrarySearchProvider.overrideWithValue(
          (query) async => derivedSearchResult(query),
        ),
      ],
    );

    final notifier = container.read(conceptGraphExplorerProvider.notifier);
    await notifier.createDraftCandidateFromLibrarySearch('attention memory');

    final state = container.read(conceptGraphExplorerProvider);
    expect(state.draftCandidate.value?.createdAny, isTrue);
    expect(state.nodes.value!.map((node) => node.id),
        contains('rag:attention-memory'));
    expect(state.nodes.value!.map((node) => node.id),
        contains('concept:attention'));
    expect(
        state.nodes.value!.map((node) => node.id), contains('concept:memory'));

    final reviewItems = await reviewStore.list(
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );
    expect(reviewItems, hasLength(2));
    expect(reviewItems.every((item) => item.status == ReviewItemStatus.pending),
        isTrue);
  });

  test('plain library RAG result leaves draft candidate action skipped',
      () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        conceptGraphStoreProvider.overrideWithValue(store),
        conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
        conceptGraphLibrarySearchProvider.overrideWithValue(
          (query) async => AiSemanticSearchLibraryResult(
            ok: true,
            query: query,
            evidence: [
              AiSemanticSearchLibraryEvidence(
                chunkId: 77,
                bookId: 7,
                bookTitle: 'Graph Notes',
                href: 'Text/rag.xhtml',
                anchor: 'Chunk 77',
                snippet: 'Book chunk evidence without derived layer.',
                jumpLink:
                    'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                score: 0.91,
                sourceRef: libraryRagRef(),
              ),
            ],
          ),
        ),
      ],
    );

    final notifier = container.read(conceptGraphExplorerProvider.notifier);
    await notifier.createDraftCandidateFromLibrarySearch('attention memory');

    final state = container.read(conceptGraphExplorerProvider);
    expect(
        state.draftCandidate.value?.skippedReason, 'missing-derived-rag-layer');
    expect(await store.listNodes(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });
}
