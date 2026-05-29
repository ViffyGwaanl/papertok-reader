import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';

void main() {
  late ConceptGraphStore store;

  setUp(() async {
    store = _FakeConceptGraphStore();
  });

  testWidgets('shows concepts, local relationships, and integrity status',
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
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Concept graph'), findsWidgets);
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('1 orphan / 1 broken'), findsOneWidget);

    await tester.tap(find.text('Attention'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Selective focus in a reading argument.'), findsWidgets);
    expect(find.text('reinforces'), findsOneWidget);
    expect(find.text('Local path'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);
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
  Future<List<ConceptNode>> listNodes() async => [attention, memory, orphan];

  @override
  Future<ConceptGraphIntegrityReport> inspectIntegrity() async {
    return const ConceptGraphIntegrityReport(
      orphanNodeIds: ['orphan'],
      brokenEdgeIds: ['broken-edge'],
    );
  }

  @override
  Future<ConceptDossier?> buildDossier(String nodeId) async {
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
    return ConceptExplorationPath(
      startNodeId: startNodeId,
      nodeIds: ['attention', 'memory'],
      returnPath: ['attention', 'memory'],
      policy: policy,
    );
  }
}
