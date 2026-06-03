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
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
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

    expect(find.text('Concept graph'), findsWidgets);
    expect(
      find.textContaining(
        'AI previews draft nodes and relations inline',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('reviewed Knowledge Cards'), findsNothing);
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
    await tester.tap(find.text('Open source').last);
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
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphLoader(),
          ),
          conceptGraphBookIndexReadinessProvider.overrideWithValue(
            (bookId) async => AiBookIndexReadiness(
              bookId: bookId,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 24,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 24,
                total: 24,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.unavailable,
                reason: 'Vec1/sqlite-vec extension is not loaded',
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 3,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 1,
              ),
            ),
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
    await tester.pumpAndSettle();

    expect(find.text('Full-book derived graph'), findsOneWidget);
    expect(find.text('Book index readiness'), findsOneWidget);
    expect(find.text('Base index'), findsOneWidget);
    expect(find.text('ANN'), findsOneWidget);
    expect(
      find.textContaining('Vec1/sqlite-vec extension is not loaded'),
      findsOneWidget,
    );
    expect(find.text('Global summary'), findsOneWidget);
    expect(find.text('Graph map'), findsOneWidget);
    expect(find.text('Book map'), findsOneWidget);
    expect(find.text('2 nodes'), findsOneWidget);
    expect(find.text('1 relation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('full-book-derived-graph-map')),
      findsOneWidget,
    );
  });

  testWidgets('wide book scoped explorer still shows index readiness',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _FakeDerivedBookConceptGraphLoader(),
          ),
          conceptGraphBookIndexReadinessProvider.overrideWithValue(
            (bookId) async => AiBookIndexReadiness(
              bookId: bookId,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 24,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 24,
                total: 24,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.unavailable,
                reason: 'Vec1/sqlite-vec extension is not loaded',
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 3,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 1,
              ),
            ),
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
    await tester.pumpAndSettle();

    expect(find.text('Full-book derived graph'), findsOneWidget);
    expect(find.text('Book index readiness'), findsOneWidget);
    expect(find.text('Base index'), findsOneWidget);
    expect(find.text('ANN'), findsOneWidget);
    expect(find.text('Global summary'), findsOneWidget);
    expect(find.text('Graph map'), findsOneWidget);
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
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Open source').last);
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.path, '/open');
    expect(opened.single.queryParameters['bookId'], '7');
  });

  testWidgets('full-book derived graph relation opens evidence details',
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book relation'), findsOneWidget);
    expect(find.text('co_occurs'), findsWidgets);
    expect(find.text('Working memory'), findsWidgets);
    expect(find.text('Attention control'), findsWidgets);
    expect(find.text('Working memory and attention co-occur.'), findsWidgets);

    await tester.tap(find.text('Open source').last);
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.path, '/open');
    expect(opened.single.queryParameters['bookId'], '7');
  });

  testWidgets('full-book derived graph relation adds a draft relation inline',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();

    final relationButtonFinder = find.byKey(
      const ValueKey('derived-relation-save-derived:edge:1'),
    );
    expect(relationButtonFinder, findsOneWidget);
    expect(find.text('Add relation to my graph'), findsOneWidget);
    await tester.tap(relationButtonFinder);
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, hasLength(2));
    expect(
      mutableStore.nodes.map((node) => node.id),
      containsAll(['derived:working-memory', 'derived:attention-control']),
    );
    expect(
      mutableStore.nodes.every(
        (node) =>
            node.ownership == AiOutputOwnership.aiGeneratedDraft &&
            node.hasEvidence,
      ),
      isTrue,
    );
    expect(mutableStore.edges, hasLength(1));
    expect(mutableStore.edges.single.id, 'derived:edge:1');
    expect(
      mutableStore.edges.single.sourceNodeId,
      'derived:working-memory',
    );
    expect(
      mutableStore.edges.single.targetNodeId,
      'derived:attention-control',
    );
    expect(mutableStore.edges.single.ownership,
        AiOutputOwnership.aiGeneratedDraft);
    expect(mutableStore.edges.single.hasEvidence, isTrue);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConceptGraphExplorerPage)),
    );
    expect(
      container.read(conceptGraphExplorerProvider).edgesById,
      contains('derived:edge:1'),
    );
    expect(reviewStore.items, isEmpty);
    expect(find.text('Added relation to my graph'), findsOneWidget);

    final graphMapAfterSave =
        find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMapAfterSave));
    await tester.pumpAndSettle();
    final savedRelationRow =
        find.text('Working memory -> Attention control').first;
    await tester.scrollUntilVisible(
      savedRelationRow,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(savedRelationRow);
    await tester.pumpAndSettle();

    final savedRelationButtonFinder = find.byKey(
      const ValueKey('derived-relation-save-derived:edge:1'),
      skipOffstage: false,
    );
    expect(savedRelationButtonFinder, findsOneWidget);
    final savedRelationButton = tester.widget<TextButton>(
      savedRelationButtonFinder,
    );
    expect(savedRelationButton.onPressed, isNull);
    expect(
      find.descendant(
        of: savedRelationButtonFinder,
        matching: find.text('Already in my graph', skipOffstage: false),
      ),
      findsOneWidget,
    );
    expect(find.text('Add relation to my graph'), findsNothing);
  });

  testWidgets('full-book derived graph relation removes a saved draft relation',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('derived-relation-save-derived:edge:1')),
    );
    await tester.pumpAndSettle();

    expect(mutableStore.edges, hasLength(1));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control').first,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Working memory -> Attention control').first);
    await tester.pumpAndSettle();

    expect(find.text('Already in my graph'), findsOneWidget);
    expect(find.text('Remove from my graph'), findsOneWidget);
    final removeButton = find.byKey(
      const ValueKey('derived-relation-remove-derived:edge:1'),
    );
    await tester.scrollUntilVisible(
      removeButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(mutableStore.edges, isEmpty);
    expect(mutableStore.nodes, hasLength(2));
    expect(reviewStore.items, isEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConceptGraphExplorerPage)),
    );
    expect(
      container.read(conceptGraphExplorerProvider).edgesById,
      isNot(contains('derived:edge:1')),
    );
    expect(find.text('Removed relation from my graph'), findsOneWidget);
    expect(find.text('Add relation to my graph'), findsOneWidget);
  });

  testWidgets('full-book derived graph relation edits and saves inline',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();

    final editButton = find.byKey(
      const ValueKey('derived-relation-edit-derived:edge:1'),
    );
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit graph relation'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('derived-relation-edit-label')),
      'helps explain',
    );
    await tester.tap(
      find.byKey(const ValueKey('derived-relation-edit-type')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('supports').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, hasLength(2));
    expect(mutableStore.edges, hasLength(1));
    expect(mutableStore.edges.single.id, 'derived:edge:1');
    expect(mutableStore.edges.single.label, 'helps explain');
    expect(mutableStore.edges.single.type, ConceptEdgeType.supports);
    expect(mutableStore.edges.single.ownership,
        AiOutputOwnership.aiGeneratedDraft);
    expect(mutableStore.edges.single.hasEvidence, isTrue);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Saved relation to my graph'), findsOneWidget);
  });

  testWidgets(
      'full-book graph ignores a derived preview relation for this page',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();

    final ignoreButton = find.byKey(
      const ValueKey('derived-relation-ignore-derived:edge:1'),
    );
    expect(ignoreButton, findsOneWidget);
    await tester.tap(ignoreButton);
    await tester.pumpAndSettle();

    expect(find.text('Ignored relation for now'), findsOneWidget);
    expect(find.text('Selected full-book relation'), findsNothing);
    expect(find.text('Working memory -> Attention control'), findsNothing);
    expect(find.text('Working memory'), findsWidgets);
    expect(find.text('Attention control'), findsWidgets);
    expect(mutableStore.edges, isEmpty);
    expect(reviewStore.items, isEmpty);
  });

  testWidgets('full-book derived graph relation merges into an existing edge',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();
    mutableStore.nodes.addAll([
      ConceptNode(
        id: 'derived:working-memory',
        type: ConceptNodeType.concept,
        label: 'Working memory',
        sourceRefs: [refFor('Existing working memory evidence.')],
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: 10,
      ),
      ConceptNode(
        id: 'derived:attention-control',
        type: ConceptNodeType.concept,
        label: 'Attention control',
        sourceRefs: [refFor('Existing attention evidence.')],
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: 11,
      ),
    ]);
    mutableStore.edges.add(
      ConceptEdge(
        id: 'existing:working-attention',
        sourceNodeId: 'derived:working-memory',
        targetNodeId: 'derived:attention-control',
        type: ConceptEdgeType.explains,
        label: 'existing explains',
        evidenceRefs: [refFor('Existing relation evidence.')],
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: 12,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Working memory -> Attention control'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Working memory -> Attention control'));
    await tester.pumpAndSettle();

    final mergeButton = find.byKey(
      const ValueKey('derived-relation-merge-derived:edge:1'),
    );
    expect(mergeButton, findsOneWidget);
    await tester.tap(mergeButton);
    await tester.pumpAndSettle();

    expect(find.text('Merge into existing relation'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'derived-relation-merge-target-existing:working-attention',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(mutableStore.edges, hasLength(1));
    expect(mutableStore.edges.single.id, 'existing:working-attention');
    expect(mutableStore.edges.single.label, 'existing explains');
    expect(mutableStore.edges.single.type, ConceptEdgeType.explains);
    expect(mutableStore.edges.single.evidenceRefs, hasLength(2));
    expect(mutableStore.edges.single.hasEvidence, isTrue);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Merged relation into existing explains'), findsOneWidget);
  });

  testWidgets('full-book derived graph node adds a draft node inline',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add to my graph'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.text('Add to my graph'));
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, hasLength(1));
    expect(mutableStore.nodes.single.id, 'derived:working-memory');
    expect(mutableStore.nodes.single.ownership,
        AiOutputOwnership.aiGeneratedDraft);
    expect(mutableStore.nodes.single.hasEvidence, isTrue);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Added to my graph'), findsOneWidget);

    final graphMapAfterSave =
        find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMapAfterSave));
    await tester.pumpAndSettle();
    expect(find.text('Already in my graph'), findsOneWidget);
  });

  testWidgets('full-book derived graph node removes a saved draft node inline',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add to my graph'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Add to my graph'));
    await tester.pumpAndSettle();
    expect(mutableStore.nodes, hasLength(1));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    expect(find.text('Already in my graph'), findsOneWidget);
    final removeButton = find.byKey(
      const ValueKey('derived-node-remove-derived:working-memory'),
    );
    expect(removeButton, findsOneWidget);
    await tester.scrollUntilVisible(
      removeButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, isEmpty);
    expect(mutableStore.edges, isEmpty);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Removed from my graph'), findsOneWidget);

    await tester.scrollUntilVisible(
      graphMap,
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    expect(find.text('Add to my graph'), findsOneWidget);
  });

  testWidgets('full-book derived graph node edits and saves inline',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    expect(find.text('Edit and save'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Edit and save'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Edit and save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit graph node'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('derived-node-edit-label')),
      'Working memory model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('derived-node-edit-summary')),
      'A user-edited explanation for the whole-book concept.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, hasLength(1));
    expect(mutableStore.nodes.single.id, 'derived:working-memory');
    expect(mutableStore.nodes.single.label, 'Working memory model');
    expect(mutableStore.nodes.single.summary,
        'A user-edited explanation for the whole-book concept.');
    expect(mutableStore.nodes.single.ownership,
        AiOutputOwnership.aiGeneratedDraft);
    expect(mutableStore.nodes.single.hasEvidence, isTrue);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Saved to my graph'), findsOneWidget);
  });

  testWidgets('full-book derived graph node merges into an existing node',
      (tester) async {
    final mutableStore = _MutableConceptGraphStore();
    final reviewStore = _MemoryReviewItemStore();
    mutableStore.nodes.add(
      ConceptNode(
        id: 'memory',
        type: ConceptNodeType.concept,
        label: 'Memory model',
        summary: 'Existing user wording stays intact.',
        sourceRefs: [refFor('Existing memory evidence.')],
        ownership: AiOutputOwnership.aiGeneratedDraft,
        createdAt: 10,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(mutableStore),
          conceptGraphReviewItemStoreProvider.overrideWithValue(reviewStore),
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
    await tester.pumpAndSettle();

    final graphMap = find.byKey(const ValueKey('full-book-derived-graph-map'));
    await tester.tapAt(tester.getCenter(graphMap));
    await tester.pumpAndSettle();

    expect(find.text('Merge'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Merge'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(find.text('Merge into existing concept'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('derived-node-merge-target-memory')),
    );
    await tester.pumpAndSettle();

    expect(mutableStore.nodes, hasLength(1));
    expect(mutableStore.nodes.single.id, 'memory');
    expect(mutableStore.nodes.single.label, 'Memory model');
    expect(mutableStore.nodes.single.summary,
        'Existing user wording stays intact.');
    expect(mutableStore.nodes.single.sourceRefs, hasLength(2));
    expect(mutableStore.nodes.single.hasEvidence, isTrue);
    expect(reviewStore.items, isEmpty);
    expect(find.text('Merged into Memory model'), findsOneWidget);
  });

  testWidgets('full-book graph centers the most connected book concept',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Book map'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Book map'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('full-book-reading-path-node-derived:central-theme'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book node'), findsOneWidget);
    expect(find.text('Central theme'), findsWidgets);
    expect(find.text('The strongest connected concept in the book.'),
        findsOneWidget);
    expect(find.text('A low-value isolated mention.'), findsNothing);
  });

  testWidgets('full-book graph shows a guided reading path from core concepts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('full-book-reading-path')),
      findsOneWidget,
    );
    expect(find.text('Reading path'), findsOneWidget);
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Central theme'), findsWidgets);
    expect(find.text('Support 1'), findsWidgets);
    expect(find.text('co_occurs'), findsWidgets);
    expect(find.text('1 evidence ref'), findsWidgets);
    expect(find.text('Isolated mention'), findsNothing);

    await tester.tap(
      find.byKey(
          const ValueKey('full-book-reading-path-node-derived:central-theme')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book node'), findsOneWidget);
    expect(find.text('Central theme evidence.'), findsOneWidget);
  });

  testWidgets('full-book reading path relation opens evidence details',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey(
          'full-book-reading-path-edge-derived:central-support-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book relation'), findsOneWidget);
    expect(find.text('co_occurs'), findsWidgets);
    expect(find.text('Central theme'), findsWidgets);
    expect(find.text('Support 1'), findsWidgets);
    expect(find.text('Central theme links to support 1.'), findsOneWidget);
  });

  testWidgets('full-book graph focuses derived path by selected text',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ConceptGraphExplorerPage(
            bookId: 7,
            initialQuery: 'Support 5 practice',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Focused by selection'), findsOneWidget);
    expect(find.text('Reading path'), findsOneWidget);
    expect(find.text('Central theme'), findsWidgets);
    expect(find.text('Support 5'), findsWidgets);
    expect(find.text('Central theme links to support 5.'), findsNothing);
    expect(find.text('Support 1'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('full-book-reading-path-edge-derived:central-support-5'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book relation'), findsOneWidget);
    expect(find.text('Central theme links to support 5.'), findsOneWidget);
  });

  testWidgets('full-book graph shows a book map summary from core evidence',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('full-book-map-summary')), findsOneWidget);
    expect(find.text('Book map'), findsOneWidget);
    expect(find.text('Core theme'), findsOneWidget);
    expect(find.text('Central theme'), findsWidgets);
    expect(find.text('8 key concepts'), findsOneWidget);
    expect(find.text('7 backbone relations'), findsOneWidget);
    expect(find.text('15 evidence refs'), findsOneWidget);
    expect(find.text('Evidence sections'), findsOneWidget);
    expect(find.text('Chapter 2: Core Argument / Chunk 4'), findsOneWidget);
    expect(
      find.text('Chapter 3: Supporting Evidence / Chunk 5'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('full-book-map-core-node-derived:central-theme'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book node'), findsOneWidget);
    expect(find.text('The strongest connected concept in the book.'),
        findsOneWidget);
  });

  testWidgets('full-book book map evidence sections open source nodes',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('full-book-map-summary')),
      const Offset(-1600, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'full-book-map-section-Chapter 3: Supporting Evidence / Chunk 5',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected full-book node'), findsOneWidget);
    expect(find.text('A supporting concept 1.'), findsOneWidget);
    expect(find.text('Support 1 evidence.'), findsOneWidget);
  });

  testWidgets('full-book graph ignores a derived preview node for this page',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _HubDerivedBookConceptGraphLoader(),
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
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('full-book-reading-path-node-derived:central-theme'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Central theme'), findsWidgets);

    expect(find.text('Ignore'), findsOneWidget);
    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(find.text('Ignored for now'), findsOneWidget);
    expect(find.text('Central theme'), findsNothing);

    expect(
      find.byKey(
        const ValueKey('full-book-reading-path-node-derived:central-theme'),
      ),
      findsNothing,
    );
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
    expect(find.text('Book map'), findsOneWidget);
    expect(find.text('2 nodes'), findsOneWidget);
    expect(find.text('1 relation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('full-book-derived-graph-map')),
      findsOneWidget,
    );
    expect(find.text('Build global layer now'), findsNothing);
  });

  testWidgets(
      'book scoped explorer does not rebuild when RAPTOR exists without graph nodes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final rebuiltBookIds = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider.overrideWithValue(store),
          conceptGraphDerivedBookLoaderProvider.overrideWithValue(
            _EmptyDerivedBookConceptGraphLoader(),
          ),
          conceptGraphGlobalLayerStatusProvider.overrideWithValue(
            (bookId) async => AiGlobalIndexBookLayerStatus(
              bookId: bookId,
              chunkCount: 4,
              raptorNodes: 2,
              graphNodes: 0,
              graphEdges: 0,
              graphCommunities: 0,
            ),
          ),
          conceptGraphBookIndexReadinessProvider.overrideWithValue(
            (bookId) async => AiBookIndexReadiness(
              bookId: bookId,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 4,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 4,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
                reason:
                    'Global summary exists, but no displayable graph nodes were extracted.',
              ),
            ),
          ),
          conceptGraphGlobalLayerRebuilderProvider.overrideWithValue(
            ({required int bookId}) async {
              rebuiltBookIds.add(bookId);
              return const AiGlobalIndexStats(
                raptorNodes: 2,
                graphNodes: 0,
                graphEdges: 0,
                graphCommunities: 0,
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
    await tester.pumpAndSettle();

    expect(find.text('Book index readiness'), findsOneWidget);
    expect(find.text('Graph map'), findsOneWidget);
    expect(find.textContaining('No displayable nodes'), findsOneWidget);
    expect(
      find.textContaining('The global summary layer exists'),
      findsOneWidget,
    );
    expect(find.text('Build global layer now'), findsNothing);
    expect(rebuiltBookIds, isEmpty);
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

  testWidgets('empty state draft candidate saves inline without Review',
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
    expect(find.text('Added to my graph'), findsOneWidget);
    expect(mutableStore.nodes.map((node) => node.label), contains('Memory'));
    expect(mutableStore.nodes.every((node) => node.hasEvidence), isTrue);
    expect(mutableStore.edges, hasLength(2));
    expect(mutableStore.edges.every((edge) => edge.hasEvidence), isTrue);
    expect(reviewStore.items, isEmpty);
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

  testWidgets(
      'empty state Card action saves a draft KnowledgeCard inline without Review',
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
      reviewStore.items.where(
        (item) => item.sourceType == ReviewItemSourceType.knowledgeCard,
      ),
      isEmpty,
    );
    expect(cardStore.cards.single.origin, KnowledgeCardOrigin.ragEvidence);
    expect(cardStore.cards.single.reviewState, KnowledgeCardReviewState.draft);
    expect(cardStore.cards.single.sourceRefs.single.canJumpBack, true);
    expect(mutableStore.nodes, isEmpty);
    expect(find.text('Saved as draft knowledge card'), findsOneWidget);
  });
}

SourceRef refFor(
  String snippet, {
  String? sourceTitle,
  String? locationLabel,
}) =>
    SourceRef(
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
      sourceTitle: sourceTitle,
      locationLabel: locationLabel,
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
  Future<List<ConceptEdge>> listEdges() async => [
        attentionMemory,
        brokenEdge,
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
  Future<bool> deleteNode(String nodeId) async {
    final id = nodeId.trim();
    final before = nodes.length;
    nodes.removeWhere((node) => node.id == id);
    final removed = nodes.length != before;
    if (removed) {
      edges.removeWhere(
        (edge) => edge.sourceNodeId == id || edge.targetNodeId == id,
      );
    }
    return removed;
  }

  @override
  Future<bool> deleteEdge(String edgeId) async {
    final id = edgeId.trim();
    final before = edges.length;
    edges.removeWhere((edge) => edge.id == id);
    return edges.length != before;
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

class _EmptyDerivedBookConceptGraphLoader
    implements DerivedBookConceptGraphLoader {
  @override
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  }) async {
    return DerivedBookConceptGraphSnapshot.empty(bookId);
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

class _HubDerivedBookConceptGraphLoader
    implements DerivedBookConceptGraphLoader {
  @override
  Future<DerivedBookConceptGraphSnapshot> loadBook({
    required int bookId,
    int nodeLimit = 18,
  }) async {
    return _hubDerivedBookGraphSnapshot(bookId);
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

DerivedBookConceptGraphSnapshot _hubDerivedBookGraphSnapshot(int bookId) {
  final nodes = [
    ConceptNode(
      id: 'derived:isolated-mention',
      type: ConceptNodeType.concept,
      label: 'Isolated mention',
      summary: 'A low-value isolated mention.',
      sourceRefs: [refFor('Isolated evidence.')],
      ownership: AiOutputOwnership.derivedCache,
    ),
    ConceptNode(
      id: 'derived:central-theme',
      type: ConceptNodeType.concept,
      label: 'Central theme',
      summary: 'The strongest connected concept in the book.',
      sourceRefs: [
        refFor(
          'Central theme evidence.',
          sourceTitle: 'Chapter 2: Core Argument',
          locationLabel: 'Chunk 4',
        ),
      ],
      ownership: AiOutputOwnership.derivedCache,
    ),
    for (var i = 1; i <= 7; i += 1)
      ConceptNode(
        id: 'derived:support-$i',
        type: ConceptNodeType.concept,
        label: 'Support $i',
        summary: 'A supporting concept $i.',
        sourceRefs: [
          refFor(
            'Support $i evidence.',
            sourceTitle: i <= 3
                ? 'Chapter 3: Supporting Evidence'
                : 'Chapter 4: Practice',
            locationLabel: 'Chunk ${i + 4}',
          ),
        ],
        ownership: AiOutputOwnership.derivedCache,
      ),
  ];
  final edges = [
    for (var i = 1; i <= 7; i += 1)
      ConceptEdge(
        id: 'derived:central-support-$i',
        sourceNodeId: 'derived:central-theme',
        targetNodeId: 'derived:support-$i',
        type: ConceptEdgeType.relatedTo,
        label: 'co_occurs',
        evidenceRefs: [refFor('Central theme links to support $i.')],
        confidence: 0.9 - (i * 0.02),
        ownership: AiOutputOwnership.derivedCache,
      ),
  ];
  return DerivedBookConceptGraphSnapshot(
    bookId: bookId,
    nodes: nodes,
    edges: edges,
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
