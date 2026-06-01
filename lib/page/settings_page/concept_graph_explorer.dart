import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/knowledge/derived_book_concept_graph_loader.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class ConceptGraphExplorerPage extends ConsumerStatefulWidget {
  const ConceptGraphExplorerPage({
    super.key,
    this.initialQuery,
    this.bookId,
    this.sourceOpener,
  });

  final String? initialQuery;
  final int? bookId;
  final PaperReaderSourceOpener? sourceOpener;

  @override
  ConsumerState<ConceptGraphExplorerPage> createState() =>
      _ConceptGraphExplorerPageState();
}

class _ConceptGraphExplorerPageState
    extends ConsumerState<ConceptGraphExplorerPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(conceptGraphExplorerProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = ref.watch(conceptGraphExplorerProvider);
    final initialQuery = widget.initialQuery?.trim();

    return SettingsSubpageScaffold(
      title: l10n.conceptGraphTitle,
      actions: [
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () =>
              ref.read(conceptGraphExplorerProvider.notifier).refresh(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(
              l10n.conceptGraphDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              l10n.conceptGraphAiModeDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
          ),
          _IntegrityBanner(state: state),
          Expanded(
            child: state.nodes.when(
              data: (nodes) => _ConceptGraphBody(
                nodes: nodes,
                state: state,
                initialQuery: initialQuery == null || initialQuery.isEmpty
                    ? null
                    : initialQuery,
                bookId: widget.bookId,
                sourceOpener: widget.sourceOpener ?? openPaperReaderSource,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ConceptGraphError(error: error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptGraphBody extends StatelessWidget {
  const _ConceptGraphBody({
    required this.nodes,
    required this.state,
    required this.initialQuery,
    required this.bookId,
    required this.sourceOpener,
  });

  final List<ConceptNode> nodes;
  final ConceptGraphExplorerState state;
  final String? initialQuery;
  final int? bookId;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context) {
    final visibleNodes = _filterNodesForQuery(nodes, initialQuery);
    List<Widget> derivedSection({required bool compact}) {
      if (bookId == null || bookId! <= 0) return const <Widget>[];
      return <Widget>[
        _DerivedBookGraphSection(bookId: bookId!, compact: compact),
        const SizedBox(height: 12),
      ];
    }

    if (visibleNodes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ...derivedSection(compact: false),
          _EmptyGraph(
            selectionQuery: initialQuery,
            state: state,
          ),
        ],
      );
    }
    final actionFeedback = _conceptGraphActionFeedback(context, state);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          return Column(
            children: [
              ...derivedSection(compact: true),
              ...actionFeedback,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _NodeListPane(
                        nodes: visibleNodes,
                        selectedId: state.selectedNodeId,
                        selectionQuery: initialQuery,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _DossierPane(
                        state: state,
                        sourceOpener: sourceOpener,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            ...derivedSection(compact: false),
            ...actionFeedback,
            SizedBox(
              height: 300,
              child: _NodeListPane(
                nodes: visibleNodes,
                selectedId: state.selectedNodeId,
                selectionQuery: initialQuery,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            _DossierPane(
              state: state,
              sourceOpener: sourceOpener,
            ),
          ],
        );
      },
    );
  }
}

class _NodeListPane extends StatelessWidget {
  const _NodeListPane({
    required this.nodes,
    required this.selectedId,
    required this.selectionQuery,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 12, 24),
  });

  final List<ConceptNode> nodes;
  final String? selectedId;
  final String? selectionQuery;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hasQuery =
        selectionQuery != null && selectionQuery!.trim().isNotEmpty;
    if (!hasQuery) {
      return _NodeList(
        nodes: nodes,
        selectedId: selectedId,
        padding: padding,
      );
    }

    final l10n = L10n.of(context);
    return ListView(
      padding: padding,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            l10n.conceptGraphRelatedToSelection,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
        ),
        _NodeList(
          nodes: nodes,
          selectedId: selectedId,
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
        ),
      ],
    );
  }
}

class _DerivedBookGraphSection extends ConsumerStatefulWidget {
  const _DerivedBookGraphSection({
    required this.bookId,
    this.compact = false,
  });

  final int bookId;
  final bool compact;

  @override
  ConsumerState<_DerivedBookGraphSection> createState() =>
      _DerivedBookGraphSectionState();
}

class _DerivedBookGraphSectionState
    extends ConsumerState<_DerivedBookGraphSection> {
  late Future<DerivedBookConceptGraphSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_DerivedBookGraphSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _future = _load();
    }
  }

  Future<DerivedBookConceptGraphSnapshot> _load() {
    return ref
        .read(conceptGraphDerivedBookLoaderProvider)
        .loadBook(bookId: widget.bookId);
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<DerivedBookConceptGraphSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        final graph = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final title = zh ? '全书派生图谱' : 'Full-book derived graph';
        final description = zh
            ? '来自当前书全局层索引的只读 GraphRAG 关系预览；它是可重建缓存，不会直接写入你的正式知识资产。'
            : 'Read-only GraphRAG relationship preview from this book global layer; it is rebuildable cache and is not saved as confirmed knowledge.';
        return DecoratedBox(
          decoration: BoxDecoration(
            color: ClaudePalette.elevated(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (graph != null && !graph.isEmpty)
                      Wrap(
                        spacing: 6,
                        children: [
                          _TinyChip(label: _nodeCountLabel(context, graph)),
                          _TinyChip(label: _edgeCountLabel(context, graph)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                      ),
                ),
                if (!loading && graph != null && graph.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    zh
                        ? '当前书还没有可展示的全书关系图。可先在 AI Index / Library Index 中补建全局层索引。'
                        : 'No full-book relationship graph is available yet. Build the global layer from AI Index / Library Index first.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                        ),
                  ),
                ],
                if (graph != null && !graph.isEmpty) ...[
                  const SizedBox(height: 12),
                  _ConceptGraphCanvas(
                    paintKey: const ValueKey('full-book-derived-graph-map'),
                    height: widget.compact ? 120 : 180,
                    nodes: graph.nodes.take(10).toList(growable: false),
                    edges: graph.edges,
                    centerNodeId: graph.nodes.first.id,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final node in graph.nodes.take(8))
                        _MapNodePill(node: node),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _nodeCountLabel(
    BuildContext context,
    DerivedBookConceptGraphSnapshot graph,
  ) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (zh) return '${graph.nodes.length} 个节点';
    return graph.nodes.length == 1 ? '1 node' : '${graph.nodes.length} nodes';
  }

  String _edgeCountLabel(
    BuildContext context,
    DerivedBookConceptGraphSnapshot graph,
  ) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (zh) return '${graph.edges.length} 条关系';
    return graph.edges.length == 1
        ? '1 relation'
        : '${graph.edges.length} relations';
  }
}

class _NodeList extends ConsumerWidget {
  const _NodeList({
    required this.nodes,
    required this.selectedId,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 12, 24),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<ConceptNode> nodes;
  final String? selectedId;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: nodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final node = nodes[index];
        final selected = node.id == selectedId;
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : ClaudePalette.card(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(_nodeIcon(node.type)),
            title:
                Text(node.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              node.summary ?? node.type.asString,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: node.hasEvidence
                ? const Icon(Icons.link_outlined, size: 18)
                : const Icon(Icons.help_outline, size: 18),
            onTap: () => ref
                .read(conceptGraphExplorerProvider.notifier)
                .selectNode(node.id),
          ),
        );
      },
    );
  }
}

class _DossierPane extends ConsumerWidget {
  const _DossierPane({
    required this.state,
    required this.sourceOpener,
  });

  final ConceptGraphExplorerState state;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return state.selection.when(
      data: (selection) {
        if (selection == null) {
          return _SelectPrompt(message: l10n.conceptGraphSelectPrompt);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: _DossierContent(
            selection: selection,
            state: state,
            sourceOpener: sourceOpener,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ConceptGraphError(error: error),
    );
  }
}

class _DossierContent extends ConsumerWidget {
  const _DossierContent({
    required this.selection,
    required this.state,
    required this.sourceOpener,
  });

  final ConceptGraphExplorerSelection selection;
  final ConceptGraphExplorerState state;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final dossier = selection.dossier;
    final sourceRefs = [
      ...dossier.node.sourceRefs,
      ...dossier.appearances,
      ...dossier.supportingEvidence,
      ...dossier.contradictingEvidence,
    ];
    final firstIntent = _firstIntent(sourceRefs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                dossier.node.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(width: 8),
            _TinyChip(label: dossier.node.type.asString),
          ],
        ),
        if (dossier.definition != null &&
            dossier.definition!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(dossier.definition!),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TinyChip(
              label: l10n.conceptGraphSourceCount(
                dossier.appearances.length,
              ),
            ),
            _TinyChip(
              label: l10n.conceptGraphRelatedCount(
                dossier.relatedEdges.length,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _LocalGraphMap(
          selection: selection,
          nodesById: state.nodesById,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.conceptGraphLocalPath,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final nodeId in selection.path.nodeIds)
              _TinyChip(label: state.nodesById[nodeId]?.label ?? nodeId),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.conceptGraphRelatedTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (dossier.relatedEdges.isEmpty)
          Text(
            l10n.conceptGraphNoRelated,
            style: TextStyle(color: ClaudePalette.secondary(context)),
          )
        else
          for (final edge in dossier.relatedEdges)
            _RelatedEdgeTile(edge: edge, nodesById: state.nodesById),
        const SizedBox(height: 16),
        Text(
          l10n.conceptGraphEvidenceTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (dossier.appearances.isEmpty)
          Text(
            l10n.conceptGraphNoEvidence,
            style: TextStyle(color: ClaudePalette.secondary(context)),
          )
        else
          for (final sourceRef in dossier.appearances)
            _EvidenceTile(sourceRef: sourceRef),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.reviewInboxOpenSourceAction),
            onPressed: firstIntent == null
                ? () => showPaperReaderSourceUnavailable(
                      context,
                      sourceRefs,
                      l10n.conceptGraphNoEvidence,
                    )
                : () => sourceOpener(
                      ref,
                      firstIntent.toUri(),
                    ),
          ),
        ),
      ],
    );
  }
}

class _LocalGraphMap extends StatelessWidget {
  const _LocalGraphMap({
    required this.selection,
    required this.nodesById,
  });

  final ConceptGraphExplorerSelection selection;
  final Map<String, ConceptNode> nodesById;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final dossier = selection.dossier;
    final directIds = _directNeighborIds(
      dossier.relatedEdges,
      dossier.node.id,
    );
    final pathIds = selection.path.nodeIds
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    final twoHopIds = pathIds
        .where((id) => id != dossier.node.id && !directIds.contains(id))
        .toList(growable: false);
    final directNodes = _nodesForIds(directIds, nodesById);
    final twoHopNodes = _nodesForIds(twoHopIds, nodesById);
    final localNodes = <ConceptNode>[
      dossier.node,
      ...directNodes,
      ...twoHopNodes,
    ];
    final evidenceLinkCount =
        dossier.relatedEdges.where((edge) => edge.hasEvidence).length;
    final draftItemCount = localNodes.where((node) => !node.isFormal).length +
        dossier.relatedEdges.where((edge) => !edge.isFormal).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.conceptGraphLocalMapTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TinyChip(label: l10n.conceptGraphMapCenter),
                _TinyChip(
                  label: l10n.conceptGraphDirectNeighborCount(
                    directNodes.length,
                  ),
                ),
                _TinyChip(
                  label: l10n.conceptGraphTwoHopCount(twoHopNodes.length),
                ),
                _TinyChip(
                  label: l10n.conceptGraphEvidenceLinkCount(
                    evidenceLinkCount,
                  ),
                ),
                _TinyChip(
                  label: l10n.conceptGraphDraftItemCount(draftItemCount),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ConceptGraphCanvas(
              nodes: localNodes.take(9).toList(growable: false),
              edges: dossier.relatedEdges,
              centerNodeId: dossier.node.id,
            ),
            const SizedBox(height: 12),
            _MapNodePill(node: dossier.node, isCenter: true),
            if (directNodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final node in directNodes) _MapNodePill(node: node),
                ],
              ),
            ],
            if (twoHopNodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final node in twoHopNodes) _MapNodePill(node: node),
                ],
              ),
            ],
            if (dossier.relatedEdges.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final edge in dossier.relatedEdges)
                _LocalGraphEdgeSummary(edge: edge, nodesById: nodesById),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConceptGraphCanvas extends StatelessWidget {
  const _ConceptGraphCanvas({
    this.paintKey = const ValueKey('concept-graph-visual-map'),
    this.height = 180,
    required this.nodes,
    required this.edges,
    required this.centerNodeId,
  });

  final Key paintKey;
  final double height;
  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final String centerNodeId;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        key: paintKey,
        painter: _ConceptGraphMapPainter(
          nodes: nodes,
          edges: edges,
          centerNodeId: centerNodeId,
          backgroundColor: ClaudePalette.card(context),
          edgeColor: colorScheme.outline.withValues(alpha: 0.58),
          evidenceEdgeColor: colorScheme.primary.withValues(alpha: 0.72),
          centerColor: colorScheme.primaryContainer,
          draftNodeColor:
              colorScheme.secondaryContainer.withValues(alpha: 0.78),
          formalNodeColor: colorScheme.tertiaryContainer.withValues(alpha: 0.9),
          nodeBorderColor: colorScheme.outline.withValues(alpha: 0.36),
          textColor: ClaudePalette.fg(context),
          mutedTextColor: ClaudePalette.secondary(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ConceptGraphMapPainter extends CustomPainter {
  const _ConceptGraphMapPainter({
    required this.nodes,
    required this.edges,
    required this.centerNodeId,
    required this.backgroundColor,
    required this.edgeColor,
    required this.evidenceEdgeColor,
    required this.centerColor,
    required this.draftNodeColor,
    required this.formalNodeColor,
    required this.nodeBorderColor,
    required this.textColor,
    required this.mutedTextColor,
  });

  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final String centerNodeId;
  final Color backgroundColor;
  final Color edgeColor;
  final Color evidenceEdgeColor;
  final Color centerColor;
  final Color draftNodeColor;
  final Color formalNodeColor;
  final Color nodeBorderColor;
  final Color textColor;
  final Color mutedTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final bounds = Offset.zero & size;
    final radius = const Radius.circular(8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, radius),
      Paint()..color = backgroundColor,
    );

    final positions = _layoutNodes(size);
    final nodeIds = positions.keys.toSet();
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final edge in edges) {
      final source = positions[edge.sourceNodeId];
      final target = positions[edge.targetNodeId];
      if (source == null || target == null) continue;
      edgePaint.color = edge.hasEvidence ? evidenceEdgeColor : edgeColor;
      canvas.drawLine(source, target, edgePaint);
      final midpoint = Offset(
        (source.dx + target.dx) / 2,
        (source.dy + target.dy) / 2,
      );
      canvas.drawCircle(
        midpoint,
        edge.hasEvidence ? 3.2 : 2.4,
        Paint()
          ..color = edge.hasEvidence ? evidenceEdgeColor : edgeColor
          ..style = PaintingStyle.fill,
      );
    }

    for (final node in nodes.where((node) => nodeIds.contains(node.id))) {
      final center = positions[node.id]!;
      final isCenter = node.id == centerNodeId;
      final nodeRadius = isCenter ? 24.0 : 19.0;
      final fill = isCenter
          ? centerColor
          : node.isFormal
              ? formalNodeColor
              : draftNodeColor;
      canvas.drawCircle(center, nodeRadius, Paint()..color = fill);
      canvas.drawCircle(
        center,
        nodeRadius,
        Paint()
          ..color = nodeBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = node.hasEvidence ? 2 : 1,
      );
      _paintLabel(
        canvas,
        node.label,
        Offset(center.dx, center.dy + nodeRadius + 10),
        maxWidth: math.min(104, size.width / 3),
        color: isCenter ? textColor : mutedTextColor,
        fontWeight: isCenter ? FontWeight.w700 : FontWeight.w500,
      );
    }
  }

  Map<String, Offset> _layoutNodes(Size size) {
    final centerNode = nodes.firstWhere(
      (node) => node.id == centerNodeId,
      orElse: () => nodes.first,
    );
    final others = nodes
        .where((node) => node.id != centerNode.id)
        .take(8)
        .toList(growable: false);
    final center = Offset(size.width / 2, size.height / 2 - 10);
    final positions = <String, Offset>{centerNode.id: center};
    if (others.isEmpty) return positions;

    final ringRadius = math.max(
      54.0,
      math.min(size.width, size.height) * 0.34,
    );
    for (var i = 0; i < others.length; i++) {
      final angle = -math.pi / 2 + (math.pi * 2 * i / others.length);
      final x = center.dx + math.cos(angle) * ringRadius;
      final y = center.dy + math.sin(angle) * ringRadius;
      positions[others[i].id] = Offset(
        x.clamp(34.0, size.width - 34.0).toDouble(),
        y.clamp(34.0, size.height - 42.0).toDouble(),
      );
    }
    return positions;
  }

  void _paintLabel(
    Canvas canvas,
    String label,
    Offset anchor, {
    required double maxWidth,
    required Color color,
    required FontWeight fontWeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          height: 1.1,
          fontWeight: fontWeight,
        ),
      ),
      maxLines: 2,
      ellipsis: '...',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(
      canvas,
      Offset(anchor.dx - painter.width / 2, anchor.dy),
    );
  }

  @override
  bool shouldRepaint(covariant _ConceptGraphMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.centerNodeId != centerNodeId ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.edgeColor != edgeColor ||
        oldDelegate.evidenceEdgeColor != evidenceEdgeColor ||
        oldDelegate.centerColor != centerColor ||
        oldDelegate.draftNodeColor != draftNodeColor ||
        oldDelegate.formalNodeColor != formalNodeColor ||
        oldDelegate.nodeBorderColor != nodeBorderColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.mutedTextColor != mutedTextColor;
  }
}

class _MapNodePill extends StatelessWidget {
  const _MapNodePill({
    required this.node,
    this.isCenter = false,
  });

  final ConceptNode node;
  final bool isCenter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isCenter
              ? colorScheme.primaryContainer
              : ClaudePalette.card(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCenter
                ? colorScheme.primary.withValues(alpha: 0.35)
                : Theme.of(context).dividerColor.withValues(alpha: 0.24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_nodeIcon(node.type), size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TinyChip(
                    label: node.isFormal
                        ? l10n.conceptGraphFormalBadge
                        : l10n.conceptGraphDraftBadge,
                  ),
                  _TinyChip(
                    label: node.hasEvidence
                        ? l10n.conceptGraphEvidenceBadge
                        : l10n.conceptGraphNoEvidenceBadge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalGraphEdgeSummary extends StatelessWidget {
  const _LocalGraphEdgeSummary({
    required this.edge,
    required this.nodesById,
  });

  final ConceptEdge edge;
  final Map<String, ConceptNode> nodesById;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sourceLabel =
        nodesById[edge.sourceNodeId]?.label ?? edge.sourceNodeId;
    final targetLabel =
        nodesById[edge.targetNodeId]?.label ?? edge.targetNodeId;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(
        '$sourceLabel -> $targetLabel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _TinyChip(label: edge.label ?? edge.type.asString),
          _TinyChip(
            label: edge.isFormal
                ? l10n.conceptGraphFormalBadge
                : l10n.conceptGraphDraftBadge,
          ),
          _TinyChip(
            label: edge.hasEvidence
                ? l10n.conceptGraphEvidenceBadge
                : l10n.conceptGraphNoEvidenceBadge,
          ),
        ],
      ),
    );
  }
}

class _RelatedEdgeTile extends StatelessWidget {
  const _RelatedEdgeTile({
    required this.edge,
    required this.nodesById,
  });

  final ConceptEdge edge;
  final Map<String, ConceptNode> nodesById;

  @override
  Widget build(BuildContext context) {
    final sourceLabel =
        nodesById[edge.sourceNodeId]?.label ?? edge.sourceNodeId;
    final targetLabel =
        nodesById[edge.targetNodeId]?.label ?? edge.targetNodeId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(edge.label ?? edge.type.asString),
      subtitle: Text('$sourceLabel -> $targetLabel'),
      trailing: edge.hasEvidence ? const Icon(Icons.link_outlined) : null,
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.sourceRef});

  final SourceRef sourceRef;

  @override
  Widget build(BuildContext context) {
    final snippet = sourceRef.sourceTextSnippet?.trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.format_quote),
      title: Text(
        snippet == null || snippet.isEmpty
            ? sourceRef.sourceKind.asString
            : snippet,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (sourceRef.sourceTitle != null) sourceRef.sourceTitle!,
          if (sourceRef.locationLabel != null) sourceRef.locationLabel!,
        ].join(' / '),
      ),
    );
  }
}

class _IntegrityBanner extends StatelessWidget {
  const _IntegrityBanner({required this.state});

  final ConceptGraphExplorerState state;

  @override
  Widget build(BuildContext context) {
    final integrity = state.integrity;
    if (integrity == null) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final hasIssues = integrity.hasIssues;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hasIssues
              ? Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35)
              : ClaudePalette.elevated(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                  hasIssues ? Icons.warning_amber : Icons.check_circle_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasIssues
                      ? l10n.conceptGraphIntegrityIssueCount(
                          integrity.orphanNodeIds.length,
                          integrity.brokenEdgeIds.length,
                        )
                      : l10n.conceptGraphIntegrityClean,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGraph extends ConsumerWidget {
  const _EmptyGraph({
    this.selectionQuery,
    required this.state,
  });

  final String? selectionQuery;
  final ConceptGraphExplorerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final hasQuery =
        selectionQuery != null && selectionQuery!.trim().isNotEmpty;
    final isCreating = state.isCreatingDraftCandidate;
    final isCreatingCard = state.isCreatingRagKnowledgeCard;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, size: 42),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? l10n.conceptGraphNoRelatedTitle
                  : l10n.conceptGraphEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? l10n.conceptGraphNoRelatedBody
                  : l10n.conceptGraphEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_link_outlined),
                    label: Text(l10n.conceptGraphCreateDraftCandidate),
                    onPressed: isCreating
                        ? null
                        : () => ref
                            .read(conceptGraphExplorerProvider.notifier)
                            .createDraftCandidateFromLibrarySearch(
                              selectionQuery!,
                            ),
                  ),
                  OutlinedButton.icon(
                    icon: isCreatingCard
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.style_outlined),
                    label: Text(l10n.contextMenuKnowledgeCard),
                    onPressed: isCreatingCard
                        ? null
                        : () => ref
                            .read(conceptGraphExplorerProvider.notifier)
                            .createKnowledgeCardFromLibrarySearch(
                              selectionQuery!,
                            ),
                  ),
                ],
              ),
              ..._conceptGraphActionFeedback(context, state),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectPrompt extends StatelessWidget {
  const _SelectPrompt({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
      ),
    );
  }
}

List<Widget> _conceptGraphActionFeedback(
  BuildContext context,
  ConceptGraphExplorerState state,
) {
  final l10n = L10n.of(context);
  final feedback = <Widget>[];
  final draftResult = state.draftCandidate.valueOrNull;
  if (!state.isCreatingDraftCandidate && draftResult != null) {
    final skippedReason = draftResult.skippedReason;
    final text = draftResult.createdAny
        ? l10n.knowledgeCardAddedToReviewInbox
        : skippedReason == null
            ? l10n.conceptGraphNoEvidence
            : '${l10n.conceptGraphNoEvidence}: $skippedReason';
    feedback.add(_ActionFeedback(text: text));
  }

  final cardResult = state.ragKnowledgeCard.valueOrNull;
  if (!state.isCreatingRagKnowledgeCard && cardResult != null) {
    final text = cardResult.addedToReviewInbox
        ? (cardResult.inserted
            ? l10n.knowledgeCardAddedToReviewInbox
            : l10n.knowledgeCardAlreadyInReviewInbox)
        : l10n.knowledgeCardAlreadySaved;
    feedback.add(_ActionFeedback(text: text));
  }

  if (feedback.isEmpty) return const <Widget>[];
  return [
    const SizedBox(height: 12),
    ...feedback,
  ];
}

class _ActionFeedback extends StatelessWidget {
  const _ActionFeedback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}

class _ConceptGraphError extends StatelessWidget {
  const _ConceptGraphError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.conceptGraphLoadFailed),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

IconData _nodeIcon(ConceptNodeType type) {
  return switch (type) {
    ConceptNodeType.concept => Icons.bubble_chart_outlined,
    ConceptNodeType.entity => Icons.person_outline,
    ConceptNodeType.claim => Icons.psychology_alt_outlined,
    ConceptNodeType.method => Icons.science_outlined,
    ConceptNodeType.book => Icons.menu_book_outlined,
    ConceptNodeType.chapter => Icons.notes_outlined,
    ConceptNodeType.card => Icons.style_outlined,
    ConceptNodeType.unknown => Icons.help_outline,
  };
}

List<String> _directNeighborIds(
  Iterable<ConceptEdge> edges,
  String centerNodeId,
) {
  final ids = <String>[];
  final seen = <String>{};
  for (final edge in edges) {
    final neighborId = edge.sourceNodeId == centerNodeId
        ? edge.targetNodeId
        : edge.targetNodeId == centerNodeId
            ? edge.sourceNodeId
            : '';
    if (neighborId.trim().isEmpty) continue;
    if (seen.add(neighborId)) ids.add(neighborId);
  }
  return ids;
}

List<ConceptNode> _nodesForIds(
  Iterable<String> ids,
  Map<String, ConceptNode> nodesById,
) {
  final nodes = <ConceptNode>[];
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) continue;
    final node = nodesById[id];
    if (node != null) nodes.add(node);
  }
  return nodes;
}

PaperReaderReaderIntent? _firstIntent(Iterable<SourceRef> refs) {
  for (final ref in refs) {
    final intent = PaperReaderReaderIntent.fromSourceRef(ref);
    if (intent != null) return intent;
  }
  return null;
}

List<ConceptNode> _filterNodesForQuery(
  List<ConceptNode> nodes,
  String? query,
) {
  final normalizedQuery = _normalizeSearchText(query ?? '');
  if (normalizedQuery.isEmpty) return nodes;

  final terms = normalizedQuery
      .split(' ')
      .where((term) => term.length >= 3)
      .toList(growable: false);
  if (terms.isEmpty) return nodes;

  return nodes.where((node) {
    final haystack = _normalizeSearchText([
      node.label,
      node.summary,
      ...node.sourceRefs.map((ref) => ref.sourceTextSnippet),
      ...node.sourceRefs.map((ref) => ref.sourceTitle),
    ].whereType<String>().join(' '));
    if (haystack.contains(normalizedQuery)) return true;
    final matchedTerms = terms.where((term) => haystack.contains(term)).length;
    final minMatches = terms.length <= 2 ? 1 : (terms.length / 2).ceil();
    return matchedTerms >= minMatches;
  }).toList(growable: false);
}

String _normalizeSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
