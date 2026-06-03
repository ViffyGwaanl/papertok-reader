import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late ConceptGraphStore graphStore;
  late ReviewItemStore reviewStore;
  late ConceptGraphProducer producer;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'concept_graph_producer_',
    );
    graphStore = ConceptGraphStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    producer = ConceptGraphProducer(
      graphStore: graphStore,
      reviewStore: reviewStore,
      now: () => 1000,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 7,
    String href = 'Text/chapter.xhtml',
    String cfi = 'epubcfi(/6/8)',
    String snippet = 'Retrieval evidence.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: href,
        cfi: cfi,
        jumpLink: 'paperreader://reader/open?bookId=$bookId&cfi=$cfi',
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({
    String id = 'kc-graph',
    List<String> conceptRefs = const ['Retrieval', 'SourceRef'],
    KnowledgeCardReviewState reviewState = KnowledgeCardReviewState.applied,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedApproved,
    List<SourceRef>? sourceRefs,
  }) =>
      KnowledgeCard(
        id: id,
        title: 'Evidence-backed retrieval',
        quote: 'Retrieval evidence.',
        explanation: 'A card can seed a local graph candidate.',
        conceptRefs: conceptRefs,
        sourceRefs: sourceRefs ?? [traceableRef()],
        reviewState: reviewState,
        ownership: ownership,
        origin: KnowledgeCardOrigin.seminar,
        createdAt: 100,
        updatedAt: 100,
      );

  SourceRef libraryRagRef({
    int bookId = 7,
    int chunkId = 42,
    String href = 'Text/chapter.xhtml',
    String snippet = 'Book chunk evidence about attention and memory.',
  }) =>
      SourceRef(
        bookId: bookId,
        chunkId: chunkId,
        href: href,
        jumpLink: 'paperreader://reader/open?bookId=$bookId&href=$href',
        sourceTitle: 'Attention Handbook',
        locationLabel: 'Chapter 1',
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.libraryRag,
        modelId: 'Qwen/Qwen3-Embedding-8B',
        algorithmVersion: 'semantic-search-library-v1',
      );

  AiSemanticSearchLibraryResult derivedRagResult({
    bool ok = true,
    String query = 'attention memory',
    String? derivedLayer = 'graph',
    String? derivedSummary =
        'GraphRAG community: Key themes: Attention, Memory. '
            'Evidence links attention control with spaced recall.',
    SourceRef? sourceRef,
  }) =>
      AiSemanticSearchLibraryResult(
        ok: ok,
        query: query,
        evidence: [
          AiSemanticSearchLibraryEvidence(
            chunkId: 42,
            bookId: 7,
            bookTitle: 'Attention Handbook',
            href: 'Text/chapter.xhtml',
            anchor: 'Chapter 1',
            snippet: 'Book chunk evidence about attention and memory.',
            jumpLink:
                'paperreader://reader/open?bookId=7&href=Text/chapter.xhtml',
            score: 0.86,
            modelId: 'Qwen/Qwen3-Embedding-8B',
            sourceRef: sourceRef ?? libraryRagRef(),
            derivedLayer: derivedLayer,
            derivedSummary: derivedSummary,
          ),
        ],
      );

  test('applied knowledge card creates draft graph candidates for review',
      () async {
    final result = await producer.createFromKnowledgeCard(card());

    expect(result.skippedReason, isNull);
    expect(result.nodes.map((node) => node.id), contains('card:kc-graph'));
    expect(result.nodes.map((node) => node.id), contains('concept:retrieval'));
    expect(result.nodes.map((node) => node.id), contains('concept:sourceref'));
    expect(result.nodes.every((node) => node.hasEvidence), isTrue);
    expect(
      result.nodes.every(
        (node) => node.ownership == AiOutputOwnership.aiGeneratedDraft,
      ),
      isTrue,
    );
    expect(result.edges, hasLength(2));
    expect(result.edges.every((edge) => edge.hasEvidence), isTrue);
    expect(
      result.edges.every(
        (edge) => edge.ownership == AiOutputOwnership.aiGeneratedDraft,
      ),
      isTrue,
    );
    expect(result.reviewItems, hasLength(2));
    expect(
      result.reviewItems.every(
        (item) =>
            item.sourceType == ReviewItemSourceType.conceptGraphRelation &&
            item.status == ReviewItemStatus.pending &&
            item.hasTraceableSource,
      ),
      isTrue,
    );

    final storedNodes = await graphStore.listNodes();
    final storedEdges = await graphStore.listEdges();
    final storedReviewItems = await reviewStore.list(
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );

    expect(storedNodes, hasLength(3));
    expect(storedEdges, hasLength(2));
    expect(storedReviewItems, hasLength(2));
  });

  test('producer is idempotent for the same knowledge card', () async {
    await producer.createFromKnowledgeCard(card());
    await producer.createFromKnowledgeCard(card());

    expect(await graphStore.listNodes(), hasLength(3));
    expect(await graphStore.listEdges(), hasLength(2));
    expect(
      await reviewStore.list(
        sourceType: ReviewItemSourceType.conceptGraphRelation,
      ),
      hasLength(2),
    );
  });

  test('non-ascii concept labels produce stable distinct node ids', () async {
    final result = await producer.createFromKnowledgeCard(
      card(id: 'kc-cn', conceptRefs: const ['注意力', '复习']),
    );

    final conceptIds = result.nodes
        .where((node) => node.type == ConceptNodeType.concept)
        .map((node) => node.id)
        .toList();

    expect(conceptIds, hasLength(2));
    expect(conceptIds.toSet(), hasLength(2));
    expect(conceptIds, isNot(contains('concept:unknown')));
  });

  test('mixed non-ascii concept labels do not collapse to ascii fragments',
      () async {
    final result = await producer.createFromKnowledgeCard(
      card(id: 'kc-mixed', conceptRefs: const ['注意力-A', '复习A']),
    );

    final conceptIds = result.nodes
        .where((node) => node.type == ConceptNodeType.concept)
        .map((node) => node.id)
        .toList();

    expect(conceptIds, hasLength(2));
    expect(conceptIds.toSet(), hasLength(2));
    expect(conceptIds, isNot(contains('concept:a')));
  });

  test('pending knowledge card does not create graph candidates', () async {
    final result = await producer.createFromKnowledgeCard(
      card(
        id: 'kc-pending',
        reviewState: KnowledgeCardReviewState.pending,
        ownership: AiOutputOwnership.aiGeneratedDraft,
      ),
    );

    expect(result.skippedReason, 'knowledge-card-not-applied');
    expect(await graphStore.listNodes(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('card without explicit concept refs does not create graph noise',
      () async {
    final result = await producer.createFromKnowledgeCard(
      card(id: 'kc-no-concepts', conceptRefs: const <String>[]),
    );

    expect(result.skippedReason, 'knowledge-card-has-no-concepts');
    expect(await graphStore.listNodes(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('derived library RAG result defaults to draft graph without Review',
      () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedRagResult(),
    );

    expect(result.skippedReason, isNull);
    expect(
        result.nodes.map((node) => node.id), contains('rag:attention-memory'));
    expect(result.nodes.map((node) => node.id), contains('concept:attention'));
    expect(result.nodes.map((node) => node.id), contains('concept:memory'));
    expect(
      result.nodes.every(
        (node) => node.ownership == AiOutputOwnership.aiGeneratedDraft,
      ),
      isTrue,
    );
    expect(result.edges, hasLength(2));
    expect(
      result.edges.every(
        (edge) =>
            edge.type == ConceptEdgeType.relatedTo &&
            edge.hasEvidence &&
            edge.ownership == AiOutputOwnership.aiGeneratedDraft,
      ),
      isTrue,
    );
    expect(result.reviewItems, isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('derived library RAG result can explicitly create relation ReviewItems',
      () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedRagResult(),
      createReviewItems: true,
    );

    expect(result.skippedReason, isNull);
    expect(result.edges, hasLength(2));
    expect(result.reviewItems, hasLength(2));
    expect(
      result.reviewItems.every(
        (item) =>
            item.sourceType == ReviewItemSourceType.conceptGraphRelation &&
            item.status == ReviewItemStatus.pending &&
            item.hasTraceableSource,
      ),
      isTrue,
    );
    expect(
      result.reviewItems.first.sourceRefs.first.sourceTextSnippet,
      'Book chunk evidence about attention and memory.',
    );
    expect(
      result.reviewItems.first.sourceRefs.first.sourceTextSnippet,
      isNot(contains('GraphRAG community')),
    );
  });

  test('derived library RAG producer is idempotent for the same result',
      () async {
    await producer.createFromLibrarySearchResult(derivedRagResult());
    await producer.createFromLibrarySearchResult(derivedRagResult());

    expect(await graphStore.listNodes(), hasLength(3));
    expect(await graphStore.listEdges(), hasLength(2));
    expect(await reviewStore.list(), isEmpty);
  });

  test('plain library RAG result does not create graph noise', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedRagResult(
        derivedLayer: null,
        derivedSummary: null,
      ),
    );

    expect(result.skippedReason, 'missing-derived-rag-layer');
    expect(await graphStore.listNodes(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('untraceable derived library RAG result is skipped', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedRagResult(
        sourceRef: SourceRef(
          sourceTextSnippet: 'Hash-only derived text.',
          sourceKind: SourceRefKind.libraryRag,
        ),
      ),
    );

    expect(result.skippedReason, 'missing-traceable-source');
    expect(await graphStore.listNodes(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('derived library RAG result without chunk hint is skipped', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedRagResult(
        sourceRef: SourceRef(
          bookId: 7,
          href: 'Text/chapter.xhtml',
          jumpLink:
              'paperreader://reader/open?bookId=7&href=Text/chapter.xhtml',
          sourceTextSnippet: 'Book anchor exists but no chunk hint.',
          sourceKind: SourceRefKind.libraryRag,
        ),
      ),
    );

    expect(result.skippedReason, 'missing-traceable-source');
    expect(await graphStore.listNodes(), isEmpty);
    expect(await graphStore.listEdges(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });
}
