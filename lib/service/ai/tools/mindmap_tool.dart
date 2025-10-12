import 'dart:async';

import 'package:anx_reader/service/ai/tools/input/mindmap_input.dart';
import 'package:anx_reader/service/ai/tools/util/mindmap_outline_parser.dart';

import 'base_tool.dart';

class MindmapTool extends RepositoryTool<MindmapInput, Map<String, dynamic>> {
  MindmapTool()
      : _parser = MindmapOutlineParser(),
        super(
          name: 'mindmap_draw',
          description:
              'Generate a mindmap structure from a hierarchical bullet-list string. Requires title and outline.',
          inputJsonSchema: const {
            'type': 'object',
            'required': ['title', 'hierarchicalList'],
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Root title for the mindmap diagram.',
              },
              'hierarchicalList': {
                'type': 'string',
                'description':
                    'Bullet list representing the node hierarchy. Use indentation to denote nesting.',
              },
            },
          },
          timeout: const Duration(seconds: 4),
        );

  final MindmapOutlineParser _parser;

  @override
  MindmapInput parseInput(Map<String, dynamic> json) {
    return MindmapInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(MindmapInput input) async {
    final result = _parser.parse(
      title: input.title,
      outline: input.hierarchicalList,
    );

    return Map<String, dynamic>.from(result.toJson());
  }
}

final mindmapTool = MindmapTool().tool;
