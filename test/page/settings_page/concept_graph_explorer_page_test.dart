import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/derived_book_concept_graph_loader.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late ConceptGraphStore store;

  setUp(() async {
    store = _FakeConceptGraphStore();
  });

  testWidgets('shows concepts, local relationships, and integrity status',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            sourceOpener: (_, uri) async => opened.add(uri),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Concept graph'), findsWidgets);
    expect(
      find.textContaining(
          'AI assists this graph through reviewed Knowledge Cards'),
      findsOneWidget,
    );
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('1 orphan / 1 broken'), findsOneWidget);

    await tester.tap(find.text('Attention'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Selective focus in a reading argument.'), findsWidgets);
    expect(find.text('reinforces'), findsWidgets);
    expect(find.text('Local path'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Open source'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.path, '/open');
    expect(opened.single.queryParameters['bookId'], '7');
    expect(opened.single.queryParameters['cfi'], 'epubcfi(/6/8)');
  });

  testWidgets('selected concept shows a local graph map summary',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Attention'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Local map'), findsOneWidget);
    expect(find.text('Center'), findsOneWidget);
    expect(find.text('1 direct'), findsOneWidget);
    expect(find.text('1 two-hop'), findsOneWidget);
    expect(find.text('1 evidence link'), findsOneWidget);
    expect(find.text('4 draft items'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('concept-graph-visual-map')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Attention -> Memory'), findsWidgets);
    expect(find.text('Recall'), findsWidgets);
  });

  testWidgets('book scoped explorer shows full-book derived graph preview',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphLoader(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(bookId: 7),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Full-book derived graph'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Working memory'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Working memory'), findsWidgets);
    expect(find.text('Attention control'), findsWidgets);
    expect(find.text('2 nodes'), findsOneWidget);
    expect(find.text('1 relation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('full-book-derived-graph-map')),
      findsOneWidget,
    );
  });

  testWidgets('full-book derived graph node opens evidence details',
      (tester) async {
    final opened = <Uri>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphLoader(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            bookId: 7,
            sourceOpener: (_, uri) async => opened.add(uri),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Working memory'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    expect(graphMap, findsOneWidget);
    expect(find.text('A whole-book graph node from the global layer.'),
        findsNothing);

    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book node'), findsOneWidget);
    expect(find.text('A whole-book graph node from the global layer.'),
        findsOneWidget);
    expect(find.text('Working memory evidence.'), findsOneWidget);

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.path, '/open');
    expect(opened.single.queryParameters['bookId'], '7');
  });

  testWidgets('book scoped explorer can build a missing global layer in place',
      (tester) async {
    final loader = _MutableDerivedBookConceptGraphLoader();
    final rebuiltBookIds = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(loader),
          conceptGraphGlobalLayerStatusProvider.overrideWithValue(
            (bookId) async {
              return AiGlobalIndexBookLayerStatus(
                bookId: bookId,
                chunkCount: 4,
                raptorNodes: loader.hasGraph ? 2 : 0,
                graphNodes: loader.hasGraph ? 2 : 0,
                graphEdges: loader.hasGraph ? 1 : 0,
                graphCommunities: loader.hasGraph ? 1 : 0,
              );
            },
          ),
          conceptGraphGlobalLayerRebuilderProvider.overrideWithValue(
            ({required int bookId}) async {
              rebuiltBookIds.add(bookId);
              loader.hasGraph = true;
              return const AiGlobalIndexStats(
                raptorNodes: 2,
                graphNodes: 2,
                graphEdges: 1,
                graphCommunities: 1,
              );
            },
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(bookId: 7),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Full-book derived graph'), findsOneWidget);
    expect(
      find.textContaining('No full-book relationship graph is available yet'),
      findsOneWidget,
    );
    await tester.pump();
    expect(find.text('Build global layer now'), findsOneWidget);

    await tester.tap(find.text('Build global layer now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(rebuiltBookIds, [7]);
    expect(find.text('Working memory'), findsWidgets);
    expect(find.text('2 nodes'), findsOneWidget);
    expect(find.text('Build global layer now'), findsNothing);
  });

  testWidgets('settings explorer can choose an indexed book full-book graph',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookCatalogProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphCatalog(),
          ),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphLoader(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Full-book auto graph'), findsOneWidget);
    expect(find.text('Working Memory Handbook'), findsWidgets);
    expect(find.text('Full-book derived graph'), findsOneWidget);
    expect(find.text('Working memory'), findsWidgets);
    expect(find.text('2 nodes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('full-book-derived-graph-map')),
      findsOneWidget,
    );
  });

  testWidgets('Open source explains concept without jumpable evidence',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            sourceOpener: (_, uri) async => opened.add(uri),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Orphan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Open source'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('No source evidence available.'), findsWidgets);
    expect(opened, isEmpty);
  });

  testWidgets('initial selection query filters related concepts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            initialQuery: 'retention after reading',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Attention'), findsNothing);
    expect(find.text('Related to selection'), findsOneWidget);
  });

  testWidgets('initial selection query shows candidate empty state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            initialQuery: 'brand new idea without graph evidence',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No related concepts yet'), findsOneWidget);
    expect(find.text('Create draft candidate'), findsOneWidget);
    expect(find.text('Attention'), findsNothing);
  });

  testWidgets('empty state create draft candidate runs derived RAG handoff',
      (tester) async {
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
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
                  snippet: 'Book chunk evidence for attention and memory.',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                  score: 0.91,
                  sourceRef: SourceRef(
                    bookId: 7,
                    href: 'Text/rag.xhtml',
                    chunkId: 77,
                    jumpLink:
                        'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                    sourceTextSnippet:
                        'Book chunk evidence for attention and memory.',
                    sourceKind: SourceRefKind.libraryRag,
                  ),
                  derivedLayer: 'graph',
                  derivedSummary:
                      'GraphRAG community: Key themes: Attention, Memory.',
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            initialQuery: 'attention memory',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Create draft candidate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No related concepts yet'), findsNothing);
    expect(find.text('attention memory'), findsWidgets);
    expect(find.text('Attention'), findsWidgets);
    expect(find.text('Added to Review inbox'), findsOneWidget);
    expect(
      reviewStore.items.where(
        (item) => item.sourceType == ReviewItemSourceType.conceptGraphRelation,
      ),
      hasLength(2),
    );
    expect(
      reviewStore.items
          .every((item) => item.status == ReviewItemStatus.pending),
      true,
    );
  });

  testWidgets('empty state draft action explains skipped handoff',
      (tester) async {
    final mutableStore = _MutableConceptGraphStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
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
                  snippet: 'Book chunk evidence without graph layer.',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                  score: 0.91,
                  sourceRef: SourceRef(
                    bookId: 7,
                    href: 'Text/rag.xhtml',
                    chunkId: 77,
                    jumpLink:
                        'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                    sourceTextSnippet:
                        'Book chunk evidence without graph layer.',
                    sourceKind: SourceRefKind.libraryRag,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            initialQuery: 'attention without graph layer',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Create draft candidate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No related concepts yet'), findsOneWidget);
    expect(find.textContaining('missing-derived-rag-layer'), findsOneWidget);
  });

  testWidgets('empty state Card action creates RAG KnowledgeCard review item',
      (tester) async {
    final mutableStore = _MutableConceptGraphStore();
    final cardStore = _MemoryKnowledgeCardStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphKnowledgeCardStoreProvider.overrideWithValue(cardStore),
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
                  snippet: 'Book chunk evidence for attention and memory.',
                  jumpLink:
                      'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                  score: 0.91,
                  sourceRef: SourceRef(
                    bookId: 7,
                    href: 'Text/rag.xhtml',
                    chunkId: 77,
                    jumpLink:
                        'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                    sourceTextSnippet:
                        'Book chunk evidence for attention and memory.',
                    sourceKind: SourceRefKind.libraryRag,
                  ),
                  derivedLayer: 'graph',
                  derivedSummary:
                      'GraphRAG community: Key themes: Attention, Memory.',
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            initialQuery: 'attention memory',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('No related concepts yet'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);

    await tester.tap(find.text('Card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      reviewStore.items
          .where(
              (item) => item.sourceType == ReviewItemSourceType.knowledgeCard)
          .length,
      1,
    );
    expect(cardStore.cards.single.origin, KnowledgeCardOrigin.ragEvidence);
    expect(mutableStore.nodes, isEmpty);
    expect(find.text('Added to Review inbox'), findsOneWidget);
  });
}

SourceRef refFor(String snippet) => SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
      sourceTextSnippet: snippet,
      sourceKind: SourceRefKind.reader,
    );

class _FakeConceptGraphStore extends ConceptGraphStore {
  _FakeConceptGraphStore();

  final attention = ConceptNode(
    id: 'attention',
    type: ConceptNodeType.concept,
    label: 'Attention',
    summary: 'Selective focus in a reading argument.',
    sourceRefs: [refFor('Attention is selective.')],
    createdAt: 100,
  );
  final memory = ConceptNode(
    id: 'memory',
    type: ConceptNodeType.concept,
    label: 'Memory',
    summary: 'Retention after reading.',
    sourceRefs: [refFor('Memory keeps useful distinctions.')],
    createdAt: 90,
  );
  final recall = ConceptNode(
    id: 'recall',
    type: ConceptNodeType.concept,
    label: 'Recall',
    summary: 'Second-hop retrieval practice.',
    sourceRefs: [refFor('Recall depends on meaningful cues.')],
    createdAt: 85,
  );
  final orphan = const ConceptNode(
    id: 'orphan',
    type: ConceptNodeType.concept,
    label: 'Orphan',
    createdAt: 80,
  );
  late final attentionMemory = ConceptEdge(
    id: 'attention-memory',
    sourceNodeId: 'attention',
    targetNodeId: 'memory',
    type: ConceptEdgeType.supports,
    label: 'reinforces',
    evidenceRefs: [refFor('Attention supports memory.')],
    createdAt: 110,
  );
  late final brokenEdge = ConceptEdge(
    id: 'broken-edge',
    sourceNodeId: 'attention',
    targetNodeId: 'missing',
    type: ConceptEdgeType.relatedTo,
    evidenceRefs: [refFor('This edge points to a missing node.')],
    createdAt: 120,
  );

  @override
  Future<List<ConceptNode>> listNodes() async => [
        attention,
        memory,
        recall,
        orphan,
      ];

  @override
  Future<ConceptGraphIntegrityReport> inspectIntegrity() async {
    return const ConceptGraphIntegrityReport(
      orphanNodeIds: ['orphan'],
      brokenEdgeIds: ['broken-edge'],
    );
  }

  @override
  Future<ConceptDossier?> buildDossier(String nodeId) async {
    if (nodeId == 'orphan') {
      return ConceptDossier(node: orphan);
    }
    if (nodeId != 'attention') return null;
    return ConceptDossier(
      node: attention,
      definition: attention.summary,
      appearances: attention.sourceRefs,
      relatedEdges: [attentionMemory],
      supportingEvidence: attentionMemory.evidenceRefs,
      recommendedNextNodeIds: ['memory'],
    );
  }

  @override
  Future<ConceptExplorationPath> exploreFrom(
    String startNodeId, {
    int requestedDepth = 2,
    ConceptExplorationPolicy policy = const ConceptExplorationPolicy(),
  }) async {
    if (startNodeId == 'orphan') {
      return ConceptExplorationPath(
        startNodeId: startNodeId,
        nodeIds: const ['orphan'],
        returnPath: const ['orphan'],
        policy: policy,
      );
    }
    return ConceptExplorationPath(
      startNodeId: startNodeId,
      nodeIds: ['attention', 'memory', 'recall'],
      returnPath: ['attention', 'memory', 'recall'],
      policy: policy,
    );
  }
}

class _MutableConceptGraphStore extends ConceptGraphStore {
  final nodes = <ConceptNode>[];
  final edges = <ConceptEdge>[];

  @override
  Future<List<ConceptNode>> listNodes() async => List<ConceptNode>.from(nodes)
    ..sort((a, b) => (b.createdAt ?? b.updatedAt ?? 0)
        .compareTo(a.createdAt ?? a.updatedAt ?? 0));

  @override
  Future<List<ConceptEdge>> listEdges() async => List<ConceptEdge>.from(edges);

  @override
  Future<ConceptNode> upsertNode(ConceptNode node) async {
    final draft = ConceptNode(
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
    final index = nodes.indexWhere((existing) => existing.id == draft.id);
    if (index >= 0) {
      nodes[index] = draft;
    } else {
      nodes.add(draft);
    }
    return draft;
  }

  @override
  Future<ConceptEdge> upsertEdge(ConceptEdge edge) async {
    final draft = ConceptEdge(
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
    final index = edges.indexWhere((existing) => existing.id == draft.id);
    if (index >= 0) {
      edges[index] = draft;
    } else {
      edges.add(draft);
    }
    return draft;
  }

  @override
  Future<ConceptGraphIntegrityReport> inspectIntegrity() async {
    final nodeIds = nodes.map((node) => node.id).toSet();
    return ConceptGraphIntegrityReport(
      orphanNodeIds:
          nodes.where((node) => node.isOrphan).map((node) => node.id).toList(),
      brokenEdgeIds: edges
          .where((edge) =>
              edge.isBroken ||
              !nodeIds.contains(edge.sourceNodeId) ||
              !nodeIds.contains(edge.targetNodeId))
          .map((edge) => edge.id)
          .toList(),
    );
  }

  @override
  Future<ConceptDossier?> buildDossier(String nodeId) async {
    ConceptNode? node;
    for (final entry in nodes) {
      if (entry.id == nodeId) {
        node = entry;
        break;
      }
    }
    if (node == null) return null;
    final relatedEdges = edges
        .where(
          (edge) =>
              edge.hasEvidence &&
              !edge.isBroken &&
              (edge.sourceNodeId == nodeId || edge.targetNodeId == nodeId),
        )
        .toList();
    return ConceptDossier(
      node: node,
      definition: node.summary,
      appearances: node.sourceRefs.where((ref) => ref.hasEvidence).toList(),
      relatedEdges: relatedEdges,
      supportingEvidence:
          relatedEdges.expand((edge) => edge.evidenceRefs).toList(),
      recommendedNextNodeIds: relatedEdges
          .map((edge) => edge.sourceNodeId == nodeId
              ? edge.targetNodeId
              : edge.sourceNodeId)
          .toList(),
    );
  }

  @override
  Future<ConceptExplorationPath> exploreFrom(
    String startNodeId, {
    int requestedDepth = 2,
    ConceptExplorationPolicy policy = const ConceptExplorationPolicy(),
  }) async {
    final related = edges
        .where((edge) =>
            edge.sourceNodeId == startNodeId ||
            edge.targetNodeId == startNodeId)
        .expand((edge) => [edge.sourceNodeId, edge.targetNodeId])
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();
    return ConceptExplorationPath(
      startNodeId: startNodeId,
      nodeIds: related.isEmpty ? [startNodeId] : related,
      returnPath: related.isEmpty ? [startNodeId] : related,
      policy: policy,
    );
  }
}

class _MemoryReviewItemStore extends ReviewItemStore {
  final _items = <String, ReviewItem>{};

  Iterable<ReviewItem> get items => _items.values;

  @override
  Future<ReviewItem?> getById(String id) async => _items[id];

  @override
  Future<ReviewItem> upsert(ReviewItem item) async {
    _items[item.id] = item;
    return item;
  }
}

class _MemoryKnowledgeCardStore extends KnowledgeCardStore {
  final cards = <KnowledgeCard>[];

  @override
  Future<KnowledgeCardStoreUpsertResult> upsertCandidate(
    KnowledgeCard candidate,
  ) async {
    for (final card in cards) {
      if (card.id == candidate.id ||
          KnowledgeCardDedupe.isLikelyDuplicate(card, candidate)) {
        return KnowledgeCardStoreUpsertResult(
          card: card,
          inserted: false,
          duplicateOfId: card.id,
        );
      }
    }
    final staged = candidate.copyWith(
      reviewState: candidate.reviewState == KnowledgeCardReviewState.draft
          ? KnowledgeCardReviewState.draft
          : KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
    cards.add(staged);
    return KnowledgeCardStoreUpsertResult(card: staged, inserted: true);
  }
}

class _FakeDerivedBookConceptGraphLoader
    implements DerivedBookConceptGraphLoader {
  @override
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  }) async {
    return _derivedBookGraphSnapshot(bookId);
  }
}

class _MutableDerivedBookConceptGraphLoader
    implements DerivedBookConceptGraphLoader {
  bool hasGraph = false;
  int loadCount = 0;

  @override
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  }) {
    loadCount++;
    if (!hasGraph) {
      return Future.value(DerivedBookConceptGraphSnapshot.empty(bookId));
    }
    return Future.value(_derivedBookGraphSnapshot(bookId));
  }
}

DerivedBookConceptGraphSnapshot _derivedBookGraphSnapshot(int bookId) {
  return DerivedBookConceptGraphSnapshot(
    bookId: bookId,
    nodes: [
      ConceptNode(
        id: 'derived:working-memory',
        type: ConceptNodeType.concept,
        label: 'Working memory',
        summary: 'A whole-book graph node from the global layer.',
        sourceRefs: [refFor('Working memory evidence.')],
        ownership: AiOutputOwnership.derivedCache,
      ),
      ConceptNode(
        id: 'derived:attention-control',
        type: ConceptNodeType.concept,
        label: 'Attention control',
        summary: 'A related full-book graph node.',
        sourceRefs: [refFor('Attention control evidence.')],
        ownership: AiOutputOwnership.derivedCache,
      ),
    ],
    edges: [
      ConceptEdge(
        id: 'derived:edge:1',
        sourceNodeId: 'derived:working-memory',
        targetNodeId: 'derived:attention-control',
        type: ConceptEdgeType.relatedTo,
        label: 'co_occurs',
        evidenceRefs: [refFor('Working memory and attention co-occur.')],
        confidence: 0.82,
        ownership: AiOutputOwnership.derivedCache,
      ),
    ],
  );
}

class _FakeDerivedBookConceptGraphCatalog
    implements DerivedBookConceptGraphCatalog {
  @override
  Future<List<DerivedBookConceptGraphBook>> listBooks({int limit = 200}) async {
    return const [
      DerivedBookConceptGraphBook(
        bookId: 7,
        title: 'Working Memory Handbook',
        chunkCount: 12,
        raptorNodes: 3,
        graphNodes: 2,
        graphEdges: 1,
      ),
    ];
  }
}
