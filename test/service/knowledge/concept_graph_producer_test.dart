import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_producer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
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
}
