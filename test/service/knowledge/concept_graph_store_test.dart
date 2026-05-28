import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('concept_graph_store_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 1,
    String href = 'Text/ch.xhtml',
    String cfi = 'epubcfi(/6/4)',
    String snippet = 'Evidence text.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: href,
        cfi: cfi,
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.libraryRag,
      );

  ConceptNode node({
    String id = 'n1',
    String label = 'Entropy',
    ConceptNodeType type = ConceptNodeType.concept,
    List<SourceRef>? sourceRefs,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    int createdAt = 100,
  }) {
    return ConceptNode(
      id: id,
      type: type,
      label: label,
      sourceRefs: sourceRefs ?? [traceableRef(snippet: label)],
      ownership: ownership,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  ConceptEdge edge({
    String id = 'e1',
    String sourceNodeId = 'n1',
    String targetNodeId = 'n2',
    ConceptEdgeType type = ConceptEdgeType.relatedTo,
    List<SourceRef>? evidenceRefs,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    int createdAt = 100,
  }) {
    return ConceptEdge(
      id: id,
      sourceNodeId: sourceNodeId,
      targetNodeId: targetNodeId,
      type: type,
      evidenceRefs: evidenceRefs ?? [traceableRef(snippet: id)],
      confidence: 0.7,
      ownership: ownership,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  test('first graph write creates versioned concept graph file', () async {
    final store = ConceptGraphStore(rootDir: tempRoot);

    await store.upsertNode(node());
    await store.upsertEdge(edge());

    final graphFile = File(
      p.join(tempRoot.path, '.knowledge', 'concept_graph_v1.json'),
    );
    expect(graphFile.existsSync(), isTrue);
    final decoded =
        jsonDecode(graphFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect(decoded['nodes'], hasLength(1));
    expect(decoded['edges'], hasLength(1));
  });

  test('dossier gathers local relations, evidence and recommended next nodes',
      () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertNode(node(id: 'n1', label: 'RAPTOR'));
    await store.upsertNode(node(id: 'n2', label: 'GraphRAG'));
    await store.upsertNode(node(id: 'n3', label: 'BM25'));
    await store.upsertEdge(
      edge(
        id: 'support',
        sourceNodeId: 'n2',
        targetNodeId: 'n1',
        type: ConceptEdgeType.supports,
      ),
    );
    await store.upsertEdge(
      edge(
        id: 'contradict',
        sourceNodeId: 'n3',
        targetNodeId: 'n1',
        type: ConceptEdgeType.contradicts,
      ),
    );

    final dossier = await store.buildDossier('n1');

    expect(dossier, isNotNull);
    expect(dossier!.node.label, 'RAPTOR');
    expect(dossier.appearances.single.hasEvidence, true);
    expect(dossier.relatedEdges.map((e) => e.id), ['support', 'contradict']);
    expect(dossier.supportingEvidence, hasLength(1));
    expect(dossier.contradictingEvidence, hasLength(1));
    expect(dossier.recommendedNextNodeIds, ['n2', 'n3']);
  });

  test('node and edge writes stay draft until review applies ownership',
      () async {
    final store = ConceptGraphStore(rootDir: tempRoot);

    await store.upsertNode(
      node(
        id: 'formal-node',
        ownership: AiOutputOwnership.aiGeneratedApproved,
      ),
    );
    await store.upsertEdge(
      edge(
        id: 'formal-edge',
        sourceNodeId: 'formal-node',
        targetNodeId: 'missing',
        ownership: AiOutputOwnership.aiGeneratedApproved,
      ),
    );

    final restoredNode = (await store.listNodes()).single;
    final restoredEdge = (await store.listEdges()).single;
    expect(restoredNode.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(restoredNode.isFormal, false);
    expect(restoredEdge.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(restoredEdge.isFormal, false);
  });

  test('applies concept relation review decision only on apply', () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertNode(node(id: 'n1'));
    await store.upsertNode(node(id: 'n2'));
    await store.upsertEdge(edge(id: 'edge-review'));
    final pending = ConceptGraphReviewAdapter.fromRelation(
      edge(id: 'edge-review'),
    );
    final approved = pending.transitionTo(
      ReviewItemStatus.approved,
      now: 200,
      decisionSource: 'user_approve',
    );
    final applied = approved.transitionTo(
      ReviewItemStatus.applied,
      now: 300,
      decisionSource: 'user_apply',
    );

    final afterApprove = await store.applyReviewDecision(approved, now: 200);
    final afterApply = await store.applyReviewDecision(applied, now: 300);

    expect(afterApprove.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(afterApprove.isFormal, false);
    expect(afterApply.ownership, AiOutputOwnership.aiGeneratedApproved);
    expect(afterApply.isFormal, true);
    final restored = (await store.listEdges())
        .singleWhere((edge) => edge.id == 'edge-review');
    expect(restored.isFormal, true);
  });

  test('rejects concept relation decisions for missing or mismatched edges',
      () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertEdge(edge(id: 'existing-edge'));

    final wrongType = ReviewItem(
      id: 'knowledge-card:kc-1',
      sourceType: ReviewItemSourceType.knowledgeCard,
      sourceId: 'kc-1',
      title: 'Wrong',
      body: 'Wrong source type',
      status: ReviewItemStatus.approved,
      sourceRefs: [traceableRef()],
    );
    final missingEdge = ConceptGraphReviewAdapter.fromRelation(
      edge(id: 'missing-edge'),
    ).transitionTo(
      ReviewItemStatus.approved,
      now: 200,
      decisionSource: 'user_approve',
    );

    expect(
      () => store.applyReviewDecision(wrongType, now: 200),
      throwsArgumentError,
    );
    expect(
      () => store.applyReviewDecision(missingEdge, now: 200),
      throwsStateError,
    );
  });

  test('dossier and exploration ignore edges without traceable evidence',
      () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertNode(node(id: 'n1'));
    await store.upsertNode(node(id: 'n2'));
    await store.upsertNode(node(id: 'n3'));
    await store.upsertEdge(
      edge(id: 'traceable', sourceNodeId: 'n1', targetNodeId: 'n2'),
    );
    await store.upsertEdge(
      const ConceptEdge(
        id: 'untraceable',
        sourceNodeId: 'n1',
        targetNodeId: 'n3',
        type: ConceptEdgeType.relatedTo,
      ),
    );

    final dossier = await store.buildDossier('n1');
    final path = await store.exploreFrom('n1');

    expect(dossier!.relatedEdges.map((e) => e.id), ['traceable']);
    expect(dossier.recommendedNextNodeIds, ['n2']);
    expect(path.nodeIds, ['n1', 'n2']);
  });

  test('integrity report detects orphan nodes and broken edges', () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertNode(
      const ConceptNode(
        id: 'orphan',
        type: ConceptNodeType.claim,
        label: 'Unverified claim',
      ),
    );
    await store.upsertNode(node(id: 'n1'));
    await store.upsertEdge(
      edge(id: 'missing-target', sourceNodeId: 'n1', targetNodeId: 'missing'),
    );

    final report = await store.inspectIntegrity();

    expect(report.orphanNodeIds, ['orphan']);
    expect(report.brokenEdgeIds, ['missing-target']);
    expect(report.hasIssues, true);
  });

  test('exploration path respects depth and width limits', () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    await store.upsertNode(node(id: 'n1'));
    await store.upsertNode(node(id: 'n2'));
    await store.upsertNode(node(id: 'n3'));
    await store.upsertNode(node(id: 'n4'));
    await store
        .upsertEdge(edge(id: 'e12', sourceNodeId: 'n1', targetNodeId: 'n2'));
    await store
        .upsertEdge(edge(id: 'e13', sourceNodeId: 'n1', targetNodeId: 'n3'));
    await store
        .upsertEdge(edge(id: 'e24', sourceNodeId: 'n2', targetNodeId: 'n4'));

    final path = await store.exploreFrom(
      'n1',
      requestedDepth: 5,
      policy: const ConceptExplorationPolicy(
        maxDepth: 1,
        maxNodesPerDepth: 1,
      ),
    );

    expect(path.nodeIds, ['n1', 'n2']);
    expect(path.returnPath, ['n1', 'n2']);
    expect(path.isWithinDepth, true);
  });

  test('exploration path applies width limit once per depth layer', () async {
    final store = ConceptGraphStore(rootDir: tempRoot);
    for (final id in ['n1', 'n2', 'n3', 'n4', 'n5', 'n6']) {
      await store.upsertNode(node(id: id));
    }
    await store
        .upsertEdge(edge(id: 'e12', sourceNodeId: 'n1', targetNodeId: 'n2'));
    await store
        .upsertEdge(edge(id: 'e13', sourceNodeId: 'n1', targetNodeId: 'n3'));
    await store
        .upsertEdge(edge(id: 'e24', sourceNodeId: 'n2', targetNodeId: 'n4'));
    await store
        .upsertEdge(edge(id: 'e25', sourceNodeId: 'n2', targetNodeId: 'n5'));
    await store
        .upsertEdge(edge(id: 'e36', sourceNodeId: 'n3', targetNodeId: 'n6'));

    final path = await store.exploreFrom(
      'n1',
      requestedDepth: 2,
      policy: const ConceptExplorationPolicy(
        maxDepth: 2,
        maxNodesPerDepth: 2,
      ),
    );

    expect(path.nodeIds, ['n1', 'n2', 'n3', 'n4', 'n5']);
  });

  test('malformed graph file degrades to an empty graph', () async {
    final graphFile = File(
      p.join(tempRoot.path, '.knowledge', 'concept_graph_v1.json'),
    );
    graphFile.createSync(recursive: true);
    graphFile.writeAsStringSync('{bad json');

    final store = ConceptGraphStore(rootDir: tempRoot);

    expect(await store.listNodes(), isEmpty);
    expect(await store.listEdges(), isEmpty);
    expect(await store.buildDossier('missing'), isNull);
  });
}
