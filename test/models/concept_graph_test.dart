import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  SourceRef ref({String? jumpLink}) => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        jumpLink: jumpLink,
        sourceTextSnippet: 'evidence',
        sourceKind: SourceRefKind.libraryRag,
      );

  test('draft concept node without evidence is orphan and not formal', () {
    const node = ConceptNode(
      id: 'n1',
      type: ConceptNodeType.concept,
      label: 'Entropy',
    );

    expect(node.hasEvidence, false);
    expect(node.isOrphan, true);
    expect(node.isFormal, false);
  });

  test('approved concept node with evidence can become formal', () {
    final node = ConceptNode(
      id: 'n1',
      type: ConceptNodeType.claim,
      label: 'The method depends on X',
      sourceRefs: [ref()],
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );

    expect(node.hasEvidence, true);
    expect(node.isFormal, true);
    final restored = ConceptNode.fromJson(node.toJson());
    expect(restored.sourceRefs.single.sourceHash, isNotNull);
  });

  test('hash-only concept evidence stays draft-level', () {
    final node = ConceptNode(
      id: 'n1',
      type: ConceptNodeType.claim,
      label: 'Detached model claim',
      sourceRefs: [
        SourceRef(
          sourceTextSnippet: 'Detached model text',
          sourceKind: SourceRefKind.external,
        ),
      ],
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );

    expect(node.sourceRefs.single.sourceHash, isNotNull);
    expect(node.hasEvidence, isFalse);
    expect(node.isFormal, isFalse);
  });

  test('concept edge requires evidence to be formal', () {
    const draft = ConceptEdge(
      id: 'e1',
      sourceNodeId: 'a',
      targetNodeId: 'b',
      type: ConceptEdgeType.supports,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    final formal = ConceptEdge(
      id: 'e2',
      sourceNodeId: 'a',
      targetNodeId: 'b',
      type: ConceptEdgeType.contradicts,
      evidenceRefs: [ref()],
      confidence: 0.7,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );

    expect(draft.isFormal, false);
    expect(formal.isFormal, true);
    expect(formal.isBroken, false);
  });

  test('dossier can expose whether a reader jump is available', () {
    final dossier = ConceptDossier(
      node: ConceptNode(
        id: 'n1',
        type: ConceptNodeType.concept,
        label: 'Motif',
        sourceRefs: [
          ref(
            jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch.xhtml',
          ),
        ],
      ),
      relatedEdges: [
        ConceptEdge(
          id: 'e1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
          type: ConceptEdgeType.relatedTo,
          evidenceRefs: [ref()],
        ),
      ],
      recommendedNextNodeIds: const ['n2'],
    );

    expect(dossier.canJumpBack, true);
    expect(dossier.toJson()['relatedEdges'], isA<List>());
  });

  test('exploration policy clamps depth and width and keeps external opt-in',
      () {
    const policy = ConceptExplorationPolicy();
    expect(policy.maxDepth, 2);
    expect(policy.maxNodesPerDepth, 7);
    expect(policy.allowExternal, false);
    expect(policy.clampDepth(10), 2);
    expect(policy.clampLayer(List.generate(20, (i) => i)), hasLength(7));

    const path = ConceptExplorationPath(
      startNodeId: 'n1',
      nodeIds: ['n1', 'n2'],
      returnPath: ['n1', 'n2'],
    );
    expect(path.isWithinDepth, true);
  });
}
