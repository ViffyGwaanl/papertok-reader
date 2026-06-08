import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/tools/concept_graph_search_tool.dart';

void main() {
  test('searches traceable concept graph nodes and edges', () async {
    final tool = ConceptGraphSearchTool(
      listNodes: () async => [
        ConceptNode(
          id: 'node-attention',
          type: ConceptNodeType.concept,
          label: '注意力机制',
          summary: '用权重分配解释上下文重点。',
          sourceRefs: [
            SourceRef(
              bookId: 1,
              href: 'chapter-3.xhtml',
              sourceTitle: 'AI Book',
              locationLabel: 'Chapter 3',
              sourceTextSnippet: '注意力机制会给不同 token 分配不同权重。',
              sourceTextForHash: 'attention-evidence',
            ),
          ],
        ),
        ConceptNode(
          id: 'node-orphan',
          type: ConceptNodeType.concept,
          label: '无证据节点',
        ),
        ConceptNode(
          id: 'node-transformer',
          type: ConceptNodeType.concept,
          label: 'Transformer',
          summary: '依赖注意力机制建模序列。',
          sourceRefs: [
            SourceRef(
              bookId: 1,
              href: 'chapter-4.xhtml',
              sourceTitle: 'AI Book',
              locationLabel: 'Chapter 4',
              sourceTextSnippet: 'Transformer 通过多头注意力建模上下文。',
              sourceTextForHash: 'transformer-evidence',
            ),
          ],
        ),
      ],
      listEdges: () async => [
        ConceptEdge(
          id: 'edge-attention-transformer',
          sourceNodeId: 'node-attention',
          targetNodeId: 'node-transformer',
          type: ConceptEdgeType.explains,
          label: '支撑 Transformer',
          evidenceRefs: [
            SourceRef(
              bookId: 1,
              href: 'chapter-4.xhtml',
              sourceTitle: 'AI Book',
              locationLabel: 'Chapter 4',
              sourceTextSnippet: '多头注意力是 Transformer 的核心组件。',
              sourceTextForHash: 'edge-evidence',
            ),
          ],
        ),
      ],
    );

    final out = await tool.run({'query': '注意力', 'limit': 10});

    expect(out['query'], '注意力');
    final results = (out['results'] as List).cast<Map<String, dynamic>>();
    expect(results, hasLength(3));
    expect(results.map((result) => result['kind']), [
      'node',
      'node',
      'edge',
    ]);
    expect(
      results.map((result) => result['id']),
      containsAll([
        'node-attention',
        'node-transformer',
        'edge-attention-transformer',
      ]),
    );
    expect(
      results.every((result) {
        final sourceRef = result['sourceRef'];
        return sourceRef is Map &&
            (sourceRef['sourceTextSnippet'] as String?)?.isNotEmpty == true;
      }),
      isTrue,
    );
    expect(
      results.map((result) => result['id']),
      isNot(contains('node-orphan')),
    );
  });
}
