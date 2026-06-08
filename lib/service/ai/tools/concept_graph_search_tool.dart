import 'dart:async';

import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';

import 'base_tool.dart';

typedef ConceptGraphNodesLoader = Future<List<ConceptNode>> Function();
typedef ConceptGraphEdgesLoader = Future<List<ConceptEdge>> Function();

class ConceptGraphSearchTool
    extends RepositoryTool<Map<String, dynamic>, Map<String, dynamic>> {
  ConceptGraphSearchTool({
    required ConceptGraphNodesLoader listNodes,
    required ConceptGraphEdgesLoader listEdges,
  })  : _listNodes = listNodes,
        _listEdges = listEdges,
        super(
          name: 'concept_graph_search',
          description:
              'Search the local concept graph for traceable concepts and relations. Returns only nodes or edges that have source evidence.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description':
                    'Text to search for in concept labels, summaries, relation labels, and evidence snippets.',
              },
              'limit': {
                'type': 'integer',
                'description':
                    'Optional. Maximum number of graph hits to return (range 1-50). Defaults to 10.',
              },
            },
            'required': ['query'],
          },
          timeout: const Duration(seconds: 5),
        );

  final ConceptGraphNodesLoader _listNodes;
  final ConceptGraphEdgesLoader _listEdges;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(Map<String, dynamic> input) async {
    final query = (input['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      throw ArgumentError('query is required');
    }
    final limitRaw = input['limit'];
    final limit = (limitRaw is num ? limitRaw.toInt() : 10).clamp(1, 50);

    final nodes = await _listNodes();
    final edges = await _listEdges();
    final nodeById = {for (final node in nodes) node.id: node};
    final results = <Map<String, dynamic>>[];

    for (final node in nodes) {
      if (results.length >= limit) break;
      final sourceRef = _firstTraceable(node.sourceRefs);
      if (sourceRef == null) continue;
      if (!_matchesQuery(query, [
        node.label,
        node.summary,
        ...node.sourceRefs.map((ref) => ref.sourceTextSnippet),
      ])) {
        continue;
      }
      results.add({
        'kind': 'node',
        'id': node.id,
        'type': node.type.asString,
        'label': node.label,
        if (node.summary?.trim().isNotEmpty == true)
          'summary': node.summary!.trim(),
        'sourceRef': sourceRef.toSafeJson(),
      });
    }

    for (final edge in edges) {
      if (results.length >= limit) break;
      final sourceRef = _firstTraceable(edge.evidenceRefs);
      if (sourceRef == null) continue;
      final sourceNode = nodeById[edge.sourceNodeId];
      final targetNode = nodeById[edge.targetNodeId];
      final relationLabel = (edge.label?.trim().isNotEmpty == true)
          ? edge.label!.trim()
          : edge.type.asString;
      if (!_matchesQuery(query, [
        relationLabel,
        edge.type.asString,
        sourceNode?.label,
        sourceNode?.summary,
        targetNode?.label,
        targetNode?.summary,
        ...edge.evidenceRefs.map((ref) => ref.sourceTextSnippet),
      ])) {
        continue;
      }
      results.add({
        'kind': 'edge',
        'id': edge.id,
        'type': edge.type.asString,
        'label': relationLabel,
        'sourceNodeId': edge.sourceNodeId,
        if (sourceNode?.label.trim().isNotEmpty == true)
          'sourceLabel': sourceNode!.label.trim(),
        'targetNodeId': edge.targetNodeId,
        if (targetNode?.label.trim().isNotEmpty == true)
          'targetLabel': targetNode!.label.trim(),
        if (edge.confidence != null) 'confidence': edge.confidence,
        'sourceRef': sourceRef.toSafeJson(),
      });
    }

    return {
      'query': query,
      'limit': limit,
      'results': results,
    };
  }

  @override
  bool shouldLogError(Object error) => error is! TimeoutException;

  static SourceRef? _firstTraceable(Iterable<SourceRef> refs) {
    for (final ref in refs) {
      if (ref.hasEvidence) return ref;
    }
    return null;
  }

  static bool _matchesQuery(String query, Iterable<String?> values) {
    final haystack = values
        .whereType<String>()
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (haystack.isEmpty) return false;
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    if (haystack.contains(normalizedQuery)) return true;
    final tokens = RegExp(r'[0-9a-zA-Z_]+|[\u4e00-\u9fff]+')
        .allMatches(normalizedQuery)
        .map((match) => match.group(0) ?? '')
        .where((token) => token.trim().length >= 2);
    for (final token in tokens) {
      if (haystack.contains(token)) return true;
    }
    return false;
  }
}

final AiToolDefinition conceptGraphSearchToolDefinition = AiToolDefinition(
  id: 'concept_graph_search',
  displayNameBuilder: (_) => 'Concept graph search',
  descriptionBuilder: (_) =>
      'Search the local concept graph for traceable concepts and relations.',
  build: (_) {
    final store = ConceptGraphStore();
    return ConceptGraphSearchTool(
      listNodes: store.listNodes,
      listEdges: store.listEdges,
    ).tool;
  },
);
