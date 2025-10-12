import 'dart:convert';

import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

class MindmapStepTile extends StatefulWidget {
  const MindmapStepTile({
    super.key,
    required this.step,
  });

  final ParsedToolStep step;

  @override
  State<MindmapStepTile> createState() => _MindmapStepTileState();
}

class _MindmapStepTileState extends State<MindmapStepTile> {
  MindmapGraphBundle? _bundle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshBundle();
  }

  @override
  void didUpdateWidget(covariant MindmapStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.output != oldWidget.step.output) {
      _refreshBundle();
    }
  }

  void _refreshBundle() {
    final output = widget.step.output;
    if (output == null || output.trim().isEmpty) {
      setState(() {
        _bundle = null;
        _error = 'Waiting for mindmap output'; // TODO: l10n
      });
      return;
    }

    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Tool output is not a JSON object');
      }

      final status = decoded['status'];
      if (status != 'ok') {
        final message = decoded['message']?.toString() ??
            'Mindmap tool returned an error'; // TODO: l10n
        throw FormatException(message);
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Mindmap payload missing data object');
      }

      final payload = MindmapPayload.fromJson(data);
      setState(() {
        _bundle = MindmapGraphBundle.fromPayload(payload);
        _error = null;
      });
    } catch (error) {
      setState(() {
        _bundle = null;
        _error = 'Failed to parse mindmap: $error'; // TODO: l10n
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = ToolTileBase.statusColorFor(widget.step.status);

    return ToolTileBase(
      title: widget.step.name,
      leadingIcon: Icons.account_tree,
      statusColor: statusColor,
      initiallyExpanded: true,
      contentBuilder: (context) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_error != null) {
      return Text(_error!, style: Theme.of(context).textTheme.bodyMedium);
    }
    final bundle = _bundle;
    if (bundle == null) {
      return Text('Mindmap is generating...',
          style: Theme.of(context).textTheme.bodyMedium); // TODO: l10n
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledContainer(
          width: double.infinity,
          height: 500,
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          radius: 12,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 320.0;
              final height = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 320.0;
              return InteractiveViewer(
                minScale: 0.4,
                maxScale: 2.5,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: GraphView.builder(
                    graph: bundle.graph,
                    algorithm: bundle.algorithm,
                    builder: (node) {
                      final id = node.key?.value?.toString() ?? '';
                      final data = bundle.lookup[id];
                      return _MindmapNodeCard(label: data?.label ?? id);
                    },
                  ),
                ),
              );
            },
          ),
        ),
        if (bundle.stats != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Nodes: ${bundle.stats!.nodeCount}, Depth: ${bundle.stats!.depth}', // TODO: l10n
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _MindmapNodeCard extends StatelessWidget {
  const _MindmapNodeCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class MindmapGraphBundle {
  MindmapGraphBundle({
    required this.graph,
    required this.algorithm,
    required this.lookup,
    required this.stats,
  });

  factory MindmapGraphBundle.fromPayload(MindmapPayload payload) {
    final graph = Graph()..isTree = true;
    final lookup = <String, MindmapNodeData>{};
    final nodeCache = <String, Node>{};

    Node ensureNode(MindmapNodeData data) {
      lookup[data.id] = data;
      return nodeCache.putIfAbsent(data.id, () => Node.Id(data.id));
    }

    void visit(MindmapNodeData node) {
      final parentNode = ensureNode(node);
      graph.addNode(parentNode);
      for (final child in node.children) {
        final childNode = ensureNode(child);
        graph.addEdge(parentNode, childNode);
        visit(child);
      }
    }

    visit(payload.root);

    final config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 10
      ..levelSeparation = 200
      ..subtreeSeparation = 20
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;

    final algorithm = MindmapAlgorithm(
      config,
      MindmapEdgeRenderer(config),
    );

    return MindmapGraphBundle(
      graph: graph,
      algorithm: algorithm,
      lookup: lookup,
      stats: payload.stats,
    );
  }

  final Graph graph;
  final Algorithm algorithm;
  final Map<String, MindmapNodeData> lookup;
  final MindmapStats? stats;
}

class MindmapPayload {
  MindmapPayload({
    required this.title,
    required this.outline,
    required this.root,
    this.stats,
  });

  factory MindmapPayload.fromJson(Map<String, dynamic> json) {
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) {
      throw const FormatException('Mindmap payload is missing root node');
    }

    return MindmapPayload(
      title: json['title']?.toString() ?? 'Mindmap', // TODO: l10n
      outline: json['outline']?.toString() ?? '',
      root: MindmapNodeData.fromJson(rootJson),
      stats: json['stats'] is Map<String, dynamic>
          ? MindmapStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }

  final String title;
  final String outline;
  final MindmapNodeData root;
  final MindmapStats? stats;
}

class MindmapNodeData {
  MindmapNodeData({
    required this.id,
    required this.label,
    required this.children,
  });

  factory MindmapNodeData.fromJson(Map<String, dynamic> json) {
    final children = (json['children'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MindmapNodeData.fromJson)
        .toList(growable: false);

    return MindmapNodeData(
      id: json['id']?.toString() ?? 'node', // TODO: l10n
      label: json['label']?.toString() ?? 'Node', // TODO: l10n
      children: children,
    );
  }

  final String id;
  final String label;
  final List<MindmapNodeData> children;
}

class MindmapStats {
  MindmapStats({required this.nodeCount, required this.depth});

  factory MindmapStats.fromJson(Map<String, dynamic> json) {
    return MindmapStats(
      nodeCount: int.tryParse(json['nodeCount']?.toString() ?? '') ?? 0,
      depth: int.tryParse(json['depth']?.toString() ?? '') ?? 0,
    );
  }

  final int nodeCount;
  final int depth;
}
