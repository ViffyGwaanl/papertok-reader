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
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
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
      if (bookId == null || bookId! <= 0) {
        return <Widget>[
          _DerivedBookGraphBrowser(
            compact: compact,
            sourceOpener: sourceOpener,
            selectionQuery: initialQuery,
          ),
          const SizedBox(height: 12),
        ];
      }
      return <Widget>[
        _DerivedBookGraphSection(
          bookId: bookId!,
          compact: compact,
          sourceOpener: sourceOpener,
          selectionQuery: initialQuery,
        ),
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
        final wide = constraints.maxWidth >= 720 && bookId != null;
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

class _DerivedBookGraphBrowser extends ConsumerStatefulWidget {
  const _DerivedBookGraphBrowser({
    this.compact = false,
    required this.sourceOpener,
    required this.selectionQuery,
  });

  final bool compact;
  final PaperReaderSourceOpener sourceOpener;
  final String? selectionQuery;

  @override
  ConsumerState<_DerivedBookGraphBrowser> createState() =>
      _DerivedBookGraphBrowserState();
}

class _DerivedBookGraphBrowserState
    extends ConsumerState<_DerivedBookGraphBrowser> {
  late Future<List<DerivedBookConceptGraphBook>> _future;
  int? _selectedBookId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DerivedBookConceptGraphBook>> _load() {
    return ref.read(conceptGraphDerivedBookCatalogProvider).listBooks();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<List<DerivedBookConceptGraphBook>>(
      future: _future,
      builder: (context, snapshot) {
        final books = snapshot.data ?? const <DerivedBookConceptGraphBook>[];
        final loading = snapshot.connectionState != ConnectionState.done;
        if ((loading && books.isEmpty) || books.isEmpty) {
          return const SizedBox.shrink();
        }
        final selectedBook = _selectedBook(books);
        final selectedBookId = selectedBook?.bookId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
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
                        const Icon(Icons.travel_explore_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            zh ? '全书自动图谱' : 'Full-book auto graph',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      zh
                          ? '选择一本已完成全局层索引的书，直接查看自动生成的只读关系图。正式知识资产仍需要 Review 确认。'
                          : 'Choose an indexed book with a global layer to inspect its generated read-only relationship graph. Confirmed knowledge still goes through Review.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.secondary(context),
                          ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedBook != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedBook.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          DropdownButton<int>(
                            key: const ValueKey(
                              'full-book-derived-graph-book-picker',
                            ),
                            isExpanded: true,
                            value: selectedBook.bookId,
                            items: [
                              for (final book in books)
                                DropdownMenuItem<int>(
                                  value: book.bookId,
                                  child: Text(
                                    book.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedBookId = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _TinyChip(
                                label: zh
                                    ? '${selectedBook.chunkCount} 个 chunk'
                                    : '${selectedBook.chunkCount} chunks',
                              ),
                              _TinyChip(
                                label: zh
                                    ? '${selectedBook.raptorNodes} 个全局摘要'
                                    : '${selectedBook.raptorNodes} summaries',
                              ),
                              _TinyChip(
                                label: zh
                                    ? '${selectedBook.graphNodes} 个图节点'
                                    : '${selectedBook.graphNodes} graph nodes',
                              ),
                              _TinyChip(
                                label: zh
                                    ? '${selectedBook.graphEdges} 条关系'
                                    : '${selectedBook.graphEdges} relations',
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (selectedBookId != null) ...[
              const SizedBox(height: 12),
              _DerivedBookGraphSection(
                bookId: selectedBookId,
                compact: widget.compact,
                sourceOpener: widget.sourceOpener,
                selectionQuery: widget.selectionQuery,
              ),
            ],
          ],
        );
      },
    );
  }

  DerivedBookConceptGraphBook? _selectedBook(
    List<DerivedBookConceptGraphBook> books,
  ) {
    if (books.isEmpty) return null;
    final selectedId = _selectedBookId;
    if (selectedId != null) {
      for (final book in books) {
        if (book.bookId == selectedId) return book;
      }
    }
    return books.first;
  }
}

class _DerivedBookGraphSection extends ConsumerStatefulWidget {
  const _DerivedBookGraphSection({
    required this.bookId,
    required this.sourceOpener,
    required this.selectionQuery,
    this.compact = false,
  });

  final int bookId;
  final PaperReaderSourceOpener sourceOpener;
  final String? selectionQuery;
  final bool compact;

  @override
  ConsumerState<_DerivedBookGraphSection> createState() =>
      _DerivedBookGraphSectionState();
}

class _DerivedBookGraphSectionState
    extends ConsumerState<_DerivedBookGraphSection> {
  late Future<DerivedBookConceptGraphSnapshot> _future;
  late Future<AiGlobalIndexBookLayerStatus?> _statusFuture;
  Future<AiBookIndexReadiness>? _readinessFuture;
  bool _isRebuilding = false;
  String? _rebuildError;
  String? _selectedNodeId;
  String? _selectedEdgeId;
  final Set<String> _ignoredDerivedNodeIds = <String>{};
  final Set<String> _ignoredDerivedEdgeIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
    _statusFuture = _loadStatus();
  }

  @override
  void didUpdateWidget(_DerivedBookGraphSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _future = _load();
      _statusFuture = _loadStatus();
      _readinessFuture = null;
      _isRebuilding = false;
      _rebuildError = null;
      _selectedNodeId = null;
      _selectedEdgeId = null;
      _ignoredDerivedNodeIds.clear();
      _ignoredDerivedEdgeIds.clear();
    }
  }

  Future<DerivedBookConceptGraphSnapshot> _load() {
    return ref
        .read(conceptGraphDerivedBookLoaderProvider)
        .loadBook(bookId: widget.bookId);
  }

  Future<AiGlobalIndexBookLayerStatus?> _loadStatus() {
    return ref.read(conceptGraphGlobalLayerStatusProvider)(widget.bookId);
  }

  Future<AiBookIndexReadiness> _loadReadiness() {
    return ref.read(conceptGraphBookIndexReadinessProvider)(widget.bookId);
  }

  Future<AiBookIndexReadiness> _ensureReadinessFuture() {
    return _readinessFuture ??= _loadReadiness();
  }

  Future<void> _rebuildGlobalLayer() async {
    if (_isRebuilding) return;
    setState(() {
      _isRebuilding = true;
      _rebuildError = null;
    });
    try {
      await ref.read(conceptGraphGlobalLayerRebuilderProvider)(
          bookId: widget.bookId);
      if (!mounted) return;
      setState(() {
        _future = _load();
        _statusFuture = _loadStatus();
        _readinessFuture = null;
        _isRebuilding = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRebuilding = false;
        _rebuildError = error.toString();
      });
    }
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
                if (!widget.compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                _BookIndexReadinessStrip(
                  readinessFuture: _ensureReadinessFuture(),
                  compact: widget.compact,
                ),
                if (!loading && graph != null && graph.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    zh
                        ? '当前书还没有可展示的全书关系图。若这本书已有旧版 AI 索引，可在这里直接补建全局层索引。'
                        : 'No full-book relationship graph is available yet. If this book already has an older AI index, build its global layer here.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                        ),
                  ),
                  const SizedBox(height: 8),
                  _GlobalLayerBuildAction(
                    statusFuture: _statusFuture,
                    isRebuilding: _isRebuilding,
                    onBuild: _rebuildGlobalLayer,
                  ),
                  if (_rebuildError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _rebuildError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                ],
                if (graph != null && !graph.isEmpty) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final visibleGraph = _visibleDerivedBookGraph(
                        graph,
                        _ignoredDerivedNodeIds,
                        _ignoredDerivedEdgeIds,
                      );
                      final focus = _focusDerivedBookGraphForQuery(
                        visibleGraph,
                        widget.selectionQuery,
                      );
                      final displayGraph = focus.graph;
                      final coreView = _coreDerivedBookGraphView(displayGraph);
                      final readingPath = _derivedBookReadingPath(displayGraph);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DerivedBookMapSummary(
                            graph: displayGraph,
                            coreView: coreView,
                            compact: widget.compact,
                            focusedBySelection: focus.isFocused,
                            onCoreNodeSelected: (node) =>
                                _handleDerivedNodeSelected(
                              displayGraph,
                              node,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!widget.compact) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TinyChip(
                                  label: zh ? '主干图' : 'Core map',
                                ),
                                _TinyChip(
                                  label: zh
                                      ? '${coreView.nodes.length} 个主干节点'
                                      : '${coreView.nodes.length} core nodes',
                                ),
                                _TinyChip(
                                  label: zh
                                      ? '${coreView.edges.length} 条主干关系'
                                      : '${coreView.edges.length} core relations',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          _ConceptGraphCanvas(
                            paintKey: const ValueKey(
                              'full-book-derived-graph-map',
                            ),
                            height: widget.compact ? 96 : 180,
                            nodes: coreView.nodes,
                            edges: coreView.edges,
                            centerNodeId: coreView.centerNodeId,
                            onNodeSelected: (node) =>
                                _handleDerivedNodeSelected(displayGraph, node),
                            onEdgeSelected: (edge) =>
                                _handleDerivedEdgeSelected(displayGraph, edge),
                          ),
                          if (readingPath.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _DerivedBookReadingPath(
                              graph: displayGraph,
                              nodes: readingPath,
                              compact: widget.compact,
                              onNodeSelected: (node) =>
                                  _handleDerivedNodeSelected(
                                displayGraph,
                                node,
                              ),
                              onEdgeSelected: (edge) =>
                                  _handleDerivedEdgeSelected(
                                displayGraph,
                                edge,
                              ),
                            ),
                          ],
                          if (displayGraph.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                zh
                                    ? '本页已忽略所有派生节点。'
                                    : 'All derived nodes are ignored for this page.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ClaudePalette.secondary(context),
                                    ),
                              ),
                            ),
                          if (!widget.compact) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final node in coreView.nodes.take(8))
                                  _MapNodePill(
                                    node: node,
                                    isCenter: node.id == _selectedNodeId ||
                                        node.id == coreView.centerNodeId &&
                                            _selectedNodeId == null,
                                    onTap: () => _handleDerivedNodeSelected(
                                      displayGraph,
                                      node,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (!widget.compact &&
                              _selectedEdge(displayGraph) != null) ...[
                            const SizedBox(height: 12),
                            _DerivedBookGraphEdgeDetails(
                              edge: _selectedEdge(displayGraph)!,
                              nodesById: {
                                for (final node in displayGraph.nodes)
                                  node.id: node,
                              },
                              sourceOpener: widget.sourceOpener,
                              onIgnore: () => _ignoreDerivedEdge(
                                _selectedEdge(displayGraph)!,
                              ),
                            ),
                          ] else if (!widget.compact &&
                              _selectedNode(displayGraph) != null) ...[
                            const SizedBox(height: 12),
                            _DerivedBookGraphNodeDetails(
                              node: _selectedNode(displayGraph)!,
                              edges: _relatedEdges(
                                displayGraph,
                                _selectedNode(displayGraph)!.id,
                              ),
                              nodesById: {
                                for (final node in displayGraph.nodes)
                                  node.id: node,
                              },
                              sourceOpener: widget.sourceOpener,
                              onEdgeSelected: (edge) =>
                                  _handleDerivedEdgeSelected(
                                displayGraph,
                                edge,
                              ),
                              onIgnore: () => _ignoreDerivedNode(
                                _selectedNode(displayGraph)!,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
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

  ConceptNode? _selectedNode(DerivedBookConceptGraphSnapshot graph) {
    final selectedId = _selectedNodeId;
    if (selectedId == null) return null;
    for (final node in graph.nodes) {
      if (node.id == selectedId) return node;
    }
    return null;
  }

  ConceptEdge? _selectedEdge(DerivedBookConceptGraphSnapshot graph) {
    final selectedId = _selectedEdgeId;
    if (selectedId == null) return null;
    for (final edge in graph.edges) {
      if (edge.id == selectedId) return edge;
    }
    return null;
  }

  List<ConceptEdge> _relatedEdges(
    DerivedBookConceptGraphSnapshot graph,
    String nodeId,
  ) {
    return graph.edges
        .where(
          (edge) => edge.sourceNodeId == nodeId || edge.targetNodeId == nodeId,
        )
        .toList(growable: false);
  }

  void _handleDerivedNodeSelected(
    DerivedBookConceptGraphSnapshot graph,
    ConceptNode node,
  ) {
    if (!widget.compact) {
      setState(() {
        _selectedNodeId = node.id;
        _selectedEdgeId = null;
      });
      return;
    }
    final edges = _relatedEdges(graph, node.id);
    final nodesById = {for (final item in graph.nodes) item.id: item};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _DerivedBookGraphNodeDetails(
              node: node,
              edges: edges,
              nodesById: nodesById,
              sourceOpener: widget.sourceOpener,
              onEdgeSelected: (edge) {
                Navigator.of(context).maybePop();
                _handleDerivedEdgeSelected(graph, edge);
              },
              onIgnore: () {
                Navigator.of(context).maybePop();
                _ignoreDerivedNode(node);
              },
            ),
          ),
        );
      },
    );
  }

  void _handleDerivedEdgeSelected(
    DerivedBookConceptGraphSnapshot graph,
    ConceptEdge edge,
  ) {
    if (!widget.compact) {
      setState(() {
        _selectedEdgeId = edge.id;
        _selectedNodeId = null;
      });
      return;
    }
    final nodesById = {for (final item in graph.nodes) item.id: item};
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _DerivedBookGraphEdgeDetails(
              edge: edge,
              nodesById: nodesById,
              sourceOpener: widget.sourceOpener,
              onIgnore: () {
                Navigator.of(context).maybePop();
                _ignoreDerivedEdge(edge);
              },
            ),
          ),
        );
      },
    );
  }

  void _ignoreDerivedNode(ConceptNode node) {
    setState(() {
      _ignoredDerivedNodeIds.add(node.id);
      if (_selectedNodeId == node.id) _selectedNodeId = null;
      _selectedEdgeId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localizations.localeOf(context).languageCode == 'zh'
              ? '已在本页忽略'
              : 'Ignored for now',
        ),
      ),
    );
  }

  void _ignoreDerivedEdge(ConceptEdge edge) {
    setState(() {
      _ignoredDerivedEdgeIds.add(edge.id);
      if (_selectedEdgeId == edge.id) _selectedEdgeId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localizations.localeOf(context).languageCode == 'zh'
              ? '已在本页忽略关系'
              : 'Ignored relation for now',
        ),
      ),
    );
  }
}

class _DerivedBookGraphNodeDetails extends ConsumerWidget {
  const _DerivedBookGraphNodeDetails({
    required this.node,
    required this.edges,
    required this.nodesById,
    required this.sourceOpener,
    this.onEdgeSelected,
    this.onIgnore,
  });

  final ConceptNode node;
  final List<ConceptEdge> edges;
  final Map<String, ConceptNode> nodesById;
  final PaperReaderSourceOpener sourceOpener;
  final ValueChanged<ConceptEdge>? onEdgeSelected;
  final VoidCallback? onIgnore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final sourceRefs = [
      ...node.sourceRefs,
      for (final edge in edges) ...edge.evidenceRefs,
    ];
    final firstIntent = _firstIntent(sourceRefs);
    final summary = node.summary?.trim();
    final graphState = ref.watch(conceptGraphExplorerProvider);
    final isSavedToGraph = graphState.nodes.valueOrNull
            ?.any((existing) => existing.id == node.id) ??
        false;
    final mergeTargets = (graphState.nodes.valueOrNull ?? const <ConceptNode>[])
        .where((existing) => existing.id != node.id)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Row(
          children: [
            const Icon(Icons.ads_click_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                zh ? '选中的全书节点' : 'Selected full-book node',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _TinyChip(
              label: zh ? '派生缓存' : 'Derived cache',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          node.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(summary),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TinyChip(
                label:
                    zh ? '${edges.length} 条相邻关系' : '${edges.length} related'),
            _TinyChip(
                label: zh
                    ? '${sourceRefs.length} 条证据'
                    : '${sourceRefs.length} evidence'),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                icon: Icon(
                  isSavedToGraph
                      ? Icons.check_circle_outline
                      : Icons.add_link_outlined,
                ),
                label: Text(
                  isSavedToGraph
                      ? (zh ? '已在我的图谱' : 'Already in my graph')
                      : (zh ? '加入我的图谱' : 'Add to my graph'),
                ),
                onPressed: node.hasEvidence && !isSavedToGraph
                    ? () => _addDerivedNodeToGraph(context, ref, zh)
                    : null,
              ),
              TextButton.icon(
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(zh ? '忽略' : 'Ignore'),
                onPressed: onIgnore,
              ),
              TextButton.icon(
                icon: const Icon(Icons.merge_type_outlined),
                label: Text(zh ? '合并' : 'Merge'),
                onPressed: node.hasEvidence && mergeTargets.isNotEmpty
                    ? () => _showMergeDerivedNodeDialog(
                          context,
                          ref,
                          zh,
                          mergeTargets,
                        )
                    : null,
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_note_outlined),
                label: Text(zh ? '编辑后保存' : 'Edit and save'),
                onPressed: node.hasEvidence
                    ? () => _showEditDerivedNodeDialog(context, ref, zh)
                    : null,
              ),
              if (isSavedToGraph)
                TextButton.icon(
                  key: ValueKey('derived-node-remove-${node.id}'),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    zh ? '从我的图谱移除' : 'Remove from my graph',
                  ),
                  onPressed: () => _removeDerivedNodeFromGraph(
                    context,
                    ref,
                    zh,
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  zh ? '打开来源' : 'Open source',
                ),
                onPressed: firstIntent == null
                    ? () => showPaperReaderSourceUnavailable(
                          context,
                          sourceRefs,
                          zh ? '没有可追踪证据。' : 'No traceable evidence.',
                        )
                    : () => sourceOpener(ref, firstIntent.toUri()),
              ),
            ],
          ),
        ),
        if (edges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            zh ? '相邻关系' : 'Related relations',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final edge in edges.take(4))
            _LocalGraphEdgeSummary(
              edge: edge,
              nodesById: nodesById,
              onTap:
                  onEdgeSelected == null ? null : () => onEdgeSelected!(edge),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          zh ? '证据' : 'Evidence',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (sourceRefs.isEmpty)
          Text(
            zh ? '没有可追踪证据。' : 'No traceable evidence.',
            style: TextStyle(color: ClaudePalette.secondary(context)),
          )
        else
          for (final sourceRef in sourceRefs.take(4))
            _EvidenceTile(sourceRef: sourceRef),
      ],
    );
  }

  Future<void> _addDerivedNodeToGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
  ) async {
    try {
      await ref
          .read(conceptGraphExplorerProvider.notifier)
          .addDerivedNodePreview(node);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(zh ? '已加入我的图谱' : 'Added to my graph'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法加入我的图谱：${error.toString()}'
                : 'Could not add to my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _removeDerivedNodeFromGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
  ) async {
    try {
      final removed = await ref
          .read(conceptGraphExplorerProvider.notifier)
          .removeSavedNode(node.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? (zh ? '已从我的图谱移除' : 'Removed from my graph')
                : (zh ? '这个概念已不在我的图谱中' : 'Concept is no longer in my graph'),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法移除图谱概念：${error.toString()}'
                : 'Could not remove concept from my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _showMergeDerivedNodeDialog(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    List<ConceptNode> targets,
  ) async {
    final target = await showDialog<ConceptNode>(
      context: context,
      builder: (_) => _DerivedNodeMergeDialog(
        targets: targets,
        zh: zh,
      ),
    );
    if (target == null) return;
    if (!context.mounted) return;
    await _mergeDerivedNodeIntoGraph(context, ref, zh, target);
  }

  Future<void> _mergeDerivedNodeIntoGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    ConceptNode target,
  ) async {
    try {
      final merged = await ref
          .read(conceptGraphExplorerProvider.notifier)
          .mergeDerivedNodePreview(
            node,
            targetNodeId: target.id,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '已合并到 ${merged.label}' : 'Merged into ${merged.label}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法合并到我的图谱：${error.toString()}'
                : 'Could not merge into my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _showEditDerivedNodeDialog(
    BuildContext context,
    WidgetRef ref,
    bool zh,
  ) async {
    final draft = await showDialog<_DerivedNodeEditDraft>(
      context: context,
      builder: (_) => _DerivedNodeEditDialog(
        node: node,
        zh: zh,
      ),
    );
    if (draft == null) return;
    if (!context.mounted) return;
    await _saveEditedDerivedNodeToGraph(context, ref, zh, draft);
  }

  Future<void> _saveEditedDerivedNodeToGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    _DerivedNodeEditDraft draft,
  ) async {
    try {
      await ref
          .read(conceptGraphExplorerProvider.notifier)
          .addDerivedNodePreview(
            ConceptNode(
              id: node.id,
              type: node.type,
              label: draft.label,
              summary: draft.summary.isEmpty ? null : draft.summary,
              sourceRefs: node.sourceRefs,
              cardIds: node.cardIds,
              ownership: AiOutputOwnership.derivedCache,
              createdAt: node.createdAt,
            ),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(zh ? '已保存到我的图谱' : 'Saved to my graph'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法保存到我的图谱：${error.toString()}'
                : 'Could not save to my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }
}

class _DerivedBookGraphEdgeDetails extends ConsumerWidget {
  const _DerivedBookGraphEdgeDetails({
    required this.edge,
    required this.nodesById,
    required this.sourceOpener,
    this.onIgnore,
  });

  final ConceptEdge edge;
  final Map<String, ConceptNode> nodesById;
  final PaperReaderSourceOpener sourceOpener;
  final VoidCallback? onIgnore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final graphState = ref.watch(conceptGraphExplorerProvider);
    final sourceNode = nodesById[edge.sourceNodeId];
    final targetNode = nodesById[edge.targetNodeId];
    final sourceLabel = sourceNode?.label ?? edge.sourceNodeId;
    final targetLabel = targetNode?.label ?? edge.targetNodeId;
    final evidenceRefs =
        edge.evidenceRefs.where((sourceRef) => sourceRef.hasEvidence).toList();
    final firstIntent = _firstIntent(evidenceRefs);
    final canAddRelation =
        sourceNode != null && targetNode != null && evidenceRefs.isNotEmpty;
    final isSavedToGraph = graphState.edgesById.containsKey(edge.id);
    final mergeTargets = (graphState.edges.valueOrNull ?? const <ConceptEdge>[])
        .where((candidate) =>
            candidate.id != edge.id &&
            candidate.hasEvidence &&
            _sameConceptEdgeEndpoints(candidate, edge))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                zh ? '选中的全书关系' : 'Selected full-book relation',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _TinyChip(label: zh ? '派生缓存' : 'Derived cache'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$sourceLabel -> $targetLabel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TinyChip(label: edge.label ?? edge.type.asString),
            _TinyChip(label: edge.type.asString),
            _TinyChip(
              label: zh
                  ? '${evidenceRefs.length} 条证据'
                  : '${evidenceRefs.length} evidence',
            ),
            if (edge.confidence != null)
              _TinyChip(
                label: zh
                    ? '置信度 ${(edge.confidence! * 100).round()}%'
                    : 'Confidence ${(edge.confidence! * 100).round()}%',
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MapNodePill(
              node: sourceNode ??
                  ConceptNode(
                    id: edge.sourceNodeId,
                    type: ConceptNodeType.unknown,
                    label: edge.sourceNodeId,
                  ),
            ),
            _MapNodePill(
              node: targetNode ??
                  ConceptNode(
                    id: edge.targetNodeId,
                    type: ConceptNodeType.unknown,
                    label: edge.targetNodeId,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: ValueKey('derived-relation-save-${edge.id}'),
                icon: Icon(
                  isSavedToGraph ? Icons.check_circle_outline : Icons.add_link,
                ),
                label: Text(
                  isSavedToGraph
                      ? (zh ? '已在我的图谱' : 'Already in my graph')
                      : (zh ? '加入我的图谱关系' : 'Add relation to my graph'),
                ),
                onPressed: canAddRelation && !isSavedToGraph
                    ? () => _addRelationToGraph(
                          context,
                          ref,
                          zh,
                          sourceNode,
                          targetNode,
                        )
                    : null,
              ),
              TextButton.icon(
                key: ValueKey('derived-relation-edit-${edge.id}'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(zh ? '编辑后保存' : 'Edit and save'),
                onPressed: canAddRelation
                    ? () => _showEditDerivedEdgeDialog(
                          context,
                          ref,
                          zh,
                          sourceNode,
                          targetNode,
                        )
                    : null,
              ),
              TextButton.icon(
                key: ValueKey('derived-relation-merge-${edge.id}'),
                icon: const Icon(Icons.merge_type_outlined),
                label: Text(zh ? '合并' : 'Merge'),
                onPressed: canAddRelation && mergeTargets.isNotEmpty
                    ? () => _showMergeDerivedEdgeDialog(
                          context,
                          ref,
                          zh,
                          mergeTargets,
                        )
                    : null,
              ),
              TextButton.icon(
                key: ValueKey('derived-relation-ignore-${edge.id}'),
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(zh ? '忽略' : 'Ignore'),
                onPressed: onIgnore,
              ),
              if (isSavedToGraph)
                TextButton.icon(
                  key: ValueKey('derived-relation-remove-${edge.id}'),
                  icon: const Icon(Icons.link_off),
                  label: Text(
                    zh ? '从我的图谱移除' : 'Remove from my graph',
                  ),
                  onPressed: () => _removeRelationFromGraph(context, ref, zh),
                ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(zh ? '打开来源' : 'Open source'),
                onPressed: firstIntent == null
                    ? () => showPaperReaderSourceUnavailable(
                          context,
                          evidenceRefs,
                          zh ? '没有可追踪证据。' : 'No traceable evidence.',
                        )
                    : () => sourceOpener(ref, firstIntent.toUri()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          zh ? '证据' : 'Evidence',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (evidenceRefs.isEmpty)
          Text(
            zh ? '没有可追踪证据。' : 'No traceable evidence.',
            style: TextStyle(color: ClaudePalette.secondary(context)),
          )
        else
          for (final sourceRef in evidenceRefs.take(4))
            _EvidenceTile(sourceRef: sourceRef),
      ],
    );
  }

  Future<void> _addRelationToGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    ConceptNode sourceNode,
    ConceptNode targetNode,
  ) async {
    try {
      await ref
          .read(conceptGraphExplorerProvider.notifier)
          .addDerivedEdgePreview(
            edge,
            sourceNode: sourceNode,
            targetNode: targetNode,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '已加入我的图谱关系' : 'Added relation to my graph',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法加入我的图谱关系：${error.toString()}'
                : 'Could not add relation to my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _showEditDerivedEdgeDialog(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    ConceptNode sourceNode,
    ConceptNode targetNode,
  ) async {
    final draft = await showDialog<_DerivedEdgeEditDraft>(
      context: context,
      builder: (_) => _DerivedEdgeEditDialog(edge: edge, zh: zh),
    );
    if (draft == null || !context.mounted) return;
    await _saveEditedRelationToGraph(
      context,
      ref,
      zh,
      sourceNode,
      targetNode,
      draft,
    );
  }

  Future<void> _showMergeDerivedEdgeDialog(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    List<ConceptEdge> targets,
  ) async {
    final target = await showDialog<ConceptEdge>(
      context: context,
      builder: (_) => _DerivedEdgeMergeDialog(
        targets: targets,
        nodesById: nodesById,
        zh: zh,
      ),
    );
    if (target == null || !context.mounted) return;
    await _mergeDerivedRelationIntoGraph(context, ref, zh, target);
  }

  Future<void> _mergeDerivedRelationIntoGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    ConceptEdge target,
  ) async {
    try {
      final merged = await ref
          .read(conceptGraphExplorerProvider.notifier)
          .mergeDerivedEdgePreview(edge, targetEdgeId: target.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '已合并到 ${_edgeDisplayLabel(merged)}'
                : 'Merged relation into ${_edgeDisplayLabel(merged)}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法合并图谱关系：${error.toString()}'
                : 'Could not merge relation into my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _saveEditedRelationToGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
    ConceptNode sourceNode,
    ConceptNode targetNode,
    _DerivedEdgeEditDraft draft,
  ) async {
    try {
      await ref
          .read(conceptGraphExplorerProvider.notifier)
          .saveEditedDerivedEdgePreview(
            edge,
            sourceNode: sourceNode,
            targetNode: targetNode,
            type: draft.type,
            label: draft.label,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '已保存到我的图谱关系' : 'Saved relation to my graph',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法保存图谱关系：${error.toString()}'
                : 'Could not save relation to my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _removeRelationFromGraph(
    BuildContext context,
    WidgetRef ref,
    bool zh,
  ) async {
    try {
      final removed = await ref
          .read(conceptGraphExplorerProvider.notifier)
          .removeSavedEdge(edge.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? (zh ? '已从我的图谱移除关系' : 'Removed relation from my graph')
                : (zh ? '这条关系已不在我的图谱中' : 'Relation is no longer in my graph'),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '无法移除图谱关系：${error.toString()}'
                : 'Could not remove relation from my graph: ${error.toString()}',
          ),
        ),
      );
    }
  }
}

class _DerivedEdgeEditDraft {
  const _DerivedEdgeEditDraft({
    required this.type,
    required this.label,
  });

  final ConceptEdgeType type;
  final String label;
}

class _DerivedNodeEditDraft {
  const _DerivedNodeEditDraft({
    required this.label,
    required this.summary,
  });

  final String label;
  final String summary;
}

class _DerivedEdgeMergeDialog extends StatelessWidget {
  const _DerivedEdgeMergeDialog({
    required this.targets,
    required this.nodesById,
    required this.zh,
  });

  final List<ConceptEdge> targets;
  final Map<String, ConceptNode> nodesById;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(zh ? '合并到已有关系' : 'Merge into existing relation'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: targets.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final target = targets[index];
            final sourceLabel =
                nodesById[target.sourceNodeId]?.label ?? target.sourceNodeId;
            final targetLabel =
                nodesById[target.targetNodeId]?.label ?? target.targetNodeId;
            return ListTile(
              key: ValueKey('derived-relation-merge-target-${target.id}'),
              leading: const Icon(Icons.merge_type_outlined),
              title: Text(_edgeDisplayLabel(target)),
              subtitle: Text(
                '$sourceLabel -> $targetLabel · ${target.type.asString}',
              ),
              onTap: () => Navigator.of(context).pop(target),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
      ],
    );
  }
}

class _DerivedEdgeEditDialog extends StatefulWidget {
  const _DerivedEdgeEditDialog({
    required this.edge,
    required this.zh,
  });

  final ConceptEdge edge;
  final bool zh;

  @override
  State<_DerivedEdgeEditDialog> createState() => _DerivedEdgeEditDialogState();
}

class _DerivedEdgeEditDialogState extends State<_DerivedEdgeEditDialog> {
  late final TextEditingController _labelController;
  late ConceptEdgeType _type;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.edge.label?.trim() ?? '');
    _type = widget.edge.type == ConceptEdgeType.unknown
        ? ConceptEdgeType.relatedTo
        : widget.edge.type;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = widget.zh;
    final edgeTypes = ConceptEdgeType.values
        .where((type) => type != ConceptEdgeType.unknown)
        .toList(growable: false);
    return AlertDialog(
      title: Text(zh ? '编辑图谱关系' : 'Edit graph relation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('derived-relation-edit-label'),
              controller: _labelController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: zh ? '关系标签' : 'Relation label',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ConceptEdgeType>(
              key: const ValueKey('derived-relation-edit-type'),
              initialValue: _type,
              decoration: InputDecoration(
                labelText: zh ? '关系类型' : 'Relation type',
              ),
              items: [
                for (final type in edgeTypes)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type.asString),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _type = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _DerivedEdgeEditDraft(
                type: _type,
                label: _labelController.text.trim(),
              ),
            );
          },
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}

class _DerivedNodeMergeDialog extends StatelessWidget {
  const _DerivedNodeMergeDialog({
    required this.targets,
    required this.zh,
  });

  final List<ConceptNode> targets;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(zh ? '合并到已有概念' : 'Merge into existing concept'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: targets.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final target = targets[index];
            return ListTile(
              key: ValueKey('derived-node-merge-target-${target.id}'),
              leading: Icon(_nodeIcon(target.type)),
              title: Text(target.label),
              subtitle: target.summary == null ? null : Text(target.summary!),
              onTap: () => Navigator.of(context).pop(target),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
      ],
    );
  }
}

class _DerivedNodeEditDialog extends StatefulWidget {
  const _DerivedNodeEditDialog({
    required this.node,
    required this.zh,
  });

  final ConceptNode node;
  final bool zh;

  @override
  State<_DerivedNodeEditDialog> createState() => _DerivedNodeEditDialogState();
}

class _DerivedNodeEditDialogState extends State<_DerivedNodeEditDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _summaryController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.node.label.trim());
    _summaryController =
        TextEditingController(text: widget.node.summary?.trim() ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = widget.zh;
    return AlertDialog(
      title: Text(zh ? '编辑图谱节点' : 'Edit graph node'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('derived-node-edit-label'),
              controller: _labelController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: zh ? '名称' : 'Label',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('derived-node-edit-summary'),
              controller: _summaryController,
              decoration: InputDecoration(
                labelText: zh ? '摘要' : 'Summary',
              ),
              maxLines: 4,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _labelController.text.trim();
            if (label.isEmpty) return;
            Navigator.of(context).pop(
              _DerivedNodeEditDraft(
                label: label,
                summary: _summaryController.text.trim(),
              ),
            );
          },
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}

class _GlobalLayerBuildAction extends StatelessWidget {
  const _GlobalLayerBuildAction({
    required this.statusFuture,
    required this.isRebuilding,
    required this.onBuild,
  });

  final Future<AiGlobalIndexBookLayerStatus?> statusFuture;
  final bool isRebuilding;
  final Future<void> Function() onBuild;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<AiGlobalIndexBookLayerStatus?>(
      future: statusFuture,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              Text(
                zh ? '正在检查全局层状态...' : 'Checking global layer status...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          );
        }
        if (status == null) {
          return Text(
            zh
                ? '当前书还没有可用的 AI chunk 索引；请先完成书籍 AI 索引。'
                : 'This book has no AI chunk index yet. Build the book AI index first.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          );
        }
        if (status.hasGlobalLayer) {
          return Text(
            zh
                ? '全局摘要层已存在；当前没有可展示关系，通常是自动概念抽取暂时不足。'
                : 'The global summary layer exists; no displayable relations were extracted yet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: isRebuilding ? null : onBuild,
              icon: isRebuilding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
              label: Text(
                isRebuilding
                    ? (zh ? '正在生成...' : 'Building...')
                    : (zh ? '立即生成全局层索引' : 'Build global layer now'),
              ),
            ),
            Text(
              zh
                  ? '${status.chunkCount} 个旧索引 chunk 将用于本地补建。'
                  : '${status.chunkCount} indexed chunks will be reused locally.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _BookIndexReadinessStrip extends StatelessWidget {
  const _BookIndexReadinessStrip({
    required this.readinessFuture,
    required this.compact,
  });

  final Future<AiBookIndexReadiness> readinessFuture;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<AiBookIndexReadiness>(
      future: readinessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final readiness = snapshot.data;
        if (readiness == null || snapshot.hasError) {
          return Text(
            zh ? '无法读取书籍索引状态。' : 'Book index readiness could not be loaded.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? '书籍索引状态' : 'Book index readiness',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReadinessTile(
                  label: zh ? '基础索引' : 'Base index',
                  readiness: readiness.baseIndex,
                  icon: Icons.library_books_outlined,
                  compact: compact,
                ),
                _ReadinessTile(
                  label: zh ? '向量层' : 'Vector layer',
                  readiness: readiness.nativeVector,
                  icon: Icons.view_in_ar_outlined,
                  compact: compact,
                ),
                _ReadinessTile(
                  label: 'ANN',
                  readiness: readiness.annVector,
                  icon: Icons.hub_outlined,
                  compact: compact,
                ),
                _ReadinessTile(
                  label: zh ? '全局摘要层' : 'Global summary',
                  readiness: readiness.globalLayer,
                  icon: Icons.schema_outlined,
                  compact: compact,
                ),
                _ReadinessTile(
                  label: zh ? '图谱层' : 'Graph map',
                  readiness: readiness.graphLayer,
                  icon: Icons.account_tree_outlined,
                  compact: compact,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  const _ReadinessTile({
    required this.label,
    required this.readiness,
    required this.icon,
    required this.compact,
  });

  final String label;
  final AiBookIndexLayerReadiness readiness;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _readinessColor(context, readiness.state);
    final reason = readiness.reason?.trim();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 118 : 142,
        maxWidth: compact ? 180 : 220,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  _readinessStatusText(context, readiness),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                ),
                if (!compact && reason != null && reason.isNotEmpty)
                  Text(
                    reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _readinessColor(BuildContext context, AiBookIndexLayerState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state) {
    AiBookIndexLayerState.ready => scheme.primary,
    AiBookIndexLayerState.running => scheme.tertiary,
    AiBookIndexLayerState.failed => scheme.error,
    AiBookIndexLayerState.unavailable => ClaudePalette.secondary(context),
    AiBookIndexLayerState.empty => ClaudePalette.secondary(context),
    AiBookIndexLayerState.missing => ClaudePalette.secondary(context),
  };
}

String _readinessStatusText(
  BuildContext context,
  AiBookIndexLayerReadiness readiness,
) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final base = switch (readiness.state) {
    AiBookIndexLayerState.ready => zh ? '已就绪' : 'Ready',
    AiBookIndexLayerState.missing => zh ? '缺失' : 'Missing',
    AiBookIndexLayerState.running => zh ? '进行中' : 'Running',
    AiBookIndexLayerState.failed => zh ? '失败' : 'Failed',
    AiBookIndexLayerState.unavailable => zh ? '暂不可用' : 'Unavailable',
    AiBookIndexLayerState.empty => zh ? '暂无可展示节点' : 'No displayable nodes',
  };
  if (readiness.total > 0) {
    return '$base · ${readiness.count}/${readiness.total}';
  }
  if (readiness.count > 0) {
    return '$base · ${readiness.count}';
  }
  return base;
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

DerivedBookConceptGraphSnapshot _visibleDerivedBookGraph(
  DerivedBookConceptGraphSnapshot graph,
  Set<String> ignoredNodeIds,
  Set<String> ignoredEdgeIds,
) {
  if (ignoredNodeIds.isEmpty && ignoredEdgeIds.isEmpty) return graph;
  final visibleNodes = graph.nodes
      .where((node) => !ignoredNodeIds.contains(node.id))
      .toList(growable: false);
  final visibleNodeIds = visibleNodes.map((node) => node.id).toSet();
  final visibleEdges = graph.edges
      .where(
        (edge) =>
            !ignoredEdgeIds.contains(edge.id) &&
            visibleNodeIds.contains(edge.sourceNodeId) &&
            visibleNodeIds.contains(edge.targetNodeId),
      )
      .toList(growable: false);
  return DerivedBookConceptGraphSnapshot(
    bookId: graph.bookId,
    nodes: visibleNodes,
    edges: visibleEdges,
  );
}

class _DerivedBookGraphFocusResult {
  const _DerivedBookGraphFocusResult({
    required this.graph,
    required this.isFocused,
  });

  final DerivedBookConceptGraphSnapshot graph;
  final bool isFocused;
}

_DerivedBookGraphFocusResult _focusDerivedBookGraphForQuery(
  DerivedBookConceptGraphSnapshot graph,
  String? query,
) {
  final normalizedQuery = _normalizeSearchText(query ?? '');
  if (graph.isEmpty || normalizedQuery.isEmpty) {
    return _DerivedBookGraphFocusResult(graph: graph, isFocused: false);
  }
  final terms = normalizedQuery
      .split(' ')
      .where((term) => term.length >= 3 || _hasAsciiDigit(term))
      .toList(growable: false);
  if (terms.isEmpty) {
    return _DerivedBookGraphFocusResult(graph: graph, isFocused: false);
  }

  final nodesById = {for (final node in graph.nodes) node.id: node};
  final matchedNodeIds = <String>{};
  for (final node in graph.nodes) {
    if (_derivedBookGraphQueryMatches(
      _derivedNodeSearchText(node),
      normalizedQuery: normalizedQuery,
      terms: terms,
    )) {
      matchedNodeIds.add(node.id);
    }
  }

  final matchedEdgeIds = <String>{};
  for (final edge in graph.edges) {
    final sourceNode = nodesById[edge.sourceNodeId];
    final targetNode = nodesById[edge.targetNodeId];
    if (_derivedBookGraphQueryMatches(
      _derivedEdgeSearchText(edge, sourceNode, targetNode),
      normalizedQuery: normalizedQuery,
      terms: terms,
    )) {
      matchedEdgeIds.add(edge.id);
    }
  }

  if (matchedNodeIds.isEmpty && matchedEdgeIds.isEmpty) {
    return _DerivedBookGraphFocusResult(graph: graph, isFocused: false);
  }

  final keepNodeIds = <String>{...matchedNodeIds};
  final keepEdgeIds = <String>{...matchedEdgeIds};
  for (final edge in graph.edges) {
    if (matchedEdgeIds.contains(edge.id) ||
        matchedNodeIds.contains(edge.sourceNodeId) ||
        matchedNodeIds.contains(edge.targetNodeId)) {
      keepEdgeIds.add(edge.id);
      keepNodeIds
        ..add(edge.sourceNodeId)
        ..add(edge.targetNodeId);
    }
  }

  final focusedNodes = graph.nodes
      .where((node) => keepNodeIds.contains(node.id))
      .toList(growable: false);
  final focusedNodeIds = focusedNodes.map((node) => node.id).toSet();
  final focusedEdges = graph.edges
      .where(
        (edge) =>
            keepEdgeIds.contains(edge.id) &&
            focusedNodeIds.contains(edge.sourceNodeId) &&
            focusedNodeIds.contains(edge.targetNodeId),
      )
      .toList(growable: false);
  if (focusedNodes.isEmpty) {
    return _DerivedBookGraphFocusResult(graph: graph, isFocused: false);
  }

  final focusedGraph = DerivedBookConceptGraphSnapshot(
    bookId: graph.bookId,
    nodes: focusedNodes,
    edges: focusedEdges,
  );
  return _DerivedBookGraphFocusResult(
    graph: focusedGraph,
    isFocused: focusedNodes.length < graph.nodes.length ||
        focusedEdges.length < graph.edges.length,
  );
}

bool _derivedBookGraphQueryMatches(
  String text, {
  required String normalizedQuery,
  required List<String> terms,
}) {
  final haystack = _normalizeSearchText(text);
  if (haystack.isEmpty) return false;
  final numericTerms = terms.where(_hasAsciiDigit).toList(growable: false);
  if (numericTerms.isNotEmpty &&
      numericTerms.any((term) => !haystack.contains(term))) {
    return false;
  }
  if (haystack.contains(normalizedQuery)) return true;
  final matchedTerms = terms.where((term) => haystack.contains(term)).length;
  final minMatches = terms.length <= 2 ? 1 : (terms.length / 2).ceil();
  return matchedTerms >= minMatches;
}

bool _hasAsciiDigit(String value) => value.contains(RegExp(r'[0-9]'));

String _derivedNodeSearchText(ConceptNode node) {
  return [
    node.label,
    node.summary,
    node.type.asString,
    ...node.sourceRefs.expand(_sourceRefSearchTerms),
  ].whereType<String>().join(' ');
}

String _derivedEdgeSearchText(
  ConceptEdge edge,
  ConceptNode? sourceNode,
  ConceptNode? targetNode,
) {
  return [
    edge.label,
    edge.type.asString,
    sourceNode?.label,
    sourceNode?.summary,
    targetNode?.label,
    targetNode?.summary,
    ...edge.evidenceRefs.expand(_sourceRefSearchTerms),
  ].whereType<String>().join(' ');
}

Iterable<String?> _sourceRefSearchTerms(SourceRef ref) sync* {
  yield ref.sourceTextSnippet;
  yield ref.sourceTitle;
}

bool _sameConceptEdgeEndpoints(ConceptEdge primary, ConceptEdge secondary) {
  final primarySourceId = primary.sourceNodeId.trim();
  final primaryTargetId = primary.targetNodeId.trim();
  final secondarySourceId = secondary.sourceNodeId.trim();
  final secondaryTargetId = secondary.targetNodeId.trim();
  if (primarySourceId.isEmpty ||
      primaryTargetId.isEmpty ||
      secondarySourceId.isEmpty ||
      secondaryTargetId.isEmpty) {
    return false;
  }
  return primarySourceId == secondarySourceId &&
          primaryTargetId == secondaryTargetId ||
      primarySourceId == secondaryTargetId &&
          primaryTargetId == secondarySourceId;
}

String _edgeDisplayLabel(ConceptEdge edge) {
  final label = edge.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  return edge.type.asString;
}

class _DerivedBookGraphCoreView {
  const _DerivedBookGraphCoreView({
    required this.nodes,
    required this.edges,
    required this.centerNodeId,
  });

  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final String centerNodeId;
}

_DerivedBookGraphCoreView _coreDerivedBookGraphView(
  DerivedBookConceptGraphSnapshot graph, {
  int nodeLimit = 10,
}) {
  if (graph.nodes.isEmpty) {
    return const _DerivedBookGraphCoreView(
      nodes: <ConceptNode>[],
      edges: <ConceptEdge>[],
      centerNodeId: '',
    );
  }
  final safeLimit = nodeLimit.clamp(2, 18).toInt();
  final originalOrder = <String, int>{
    for (var index = 0; index < graph.nodes.length; index++)
      graph.nodes[index].id: index,
  };
  final scores = _scoreDerivedBookGraphNodes(graph);
  final sortedNodes = graph.nodes.toList(growable: false)
    ..sort((a, b) {
      final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
      if (scoreCompare != 0) return scoreCompare;
      final evidenceCompare =
          b.sourceRefs.length.compareTo(a.sourceRefs.length);
      if (evidenceCompare != 0) return evidenceCompare;
      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    });
  final centerNode = sortedNodes.first;
  final selected = <String, ConceptNode>{centerNode.id: centerNode};

  final incidentEdges = graph.edges
      .where(
        (edge) =>
            edge.sourceNodeId == centerNode.id ||
            edge.targetNodeId == centerNode.id,
      )
      .toList(growable: false)
    ..sort((a, b) {
      final confidenceCompare =
          (b.confidence ?? 0).compareTo(a.confidence ?? 0);
      if (confidenceCompare != 0) return confidenceCompare;
      final evidenceCompare =
          b.evidenceRefs.length.compareTo(a.evidenceRefs.length);
      if (evidenceCompare != 0) return evidenceCompare;
      return a.id.compareTo(b.id);
    });

  final nodesById = {for (final node in graph.nodes) node.id: node};
  for (final edge in incidentEdges) {
    if (selected.length >= safeLimit) break;
    final neighborId = edge.sourceNodeId == centerNode.id
        ? edge.targetNodeId
        : edge.sourceNodeId;
    final neighbor = nodesById[neighborId];
    if (neighbor != null) selected[neighbor.id] = neighbor;
  }
  for (final node in sortedNodes) {
    if (selected.length >= safeLimit) break;
    selected[node.id] = node;
  }

  final selectedIds = selected.keys.toSet();
  final selectedEdges = graph.edges
      .where(
        (edge) =>
            selectedIds.contains(edge.sourceNodeId) &&
            selectedIds.contains(edge.targetNodeId),
      )
      .toList(growable: false)
    ..sort((a, b) {
      final confidenceCompare =
          (b.confidence ?? 0).compareTo(a.confidence ?? 0);
      if (confidenceCompare != 0) return confidenceCompare;
      return a.id.compareTo(b.id);
    });

  return _DerivedBookGraphCoreView(
    nodes: selected.values.toList(growable: false),
    edges: selectedEdges,
    centerNodeId: centerNode.id,
  );
}

List<ConceptNode> _derivedBookReadingPath(
  DerivedBookConceptGraphSnapshot graph, {
  int nodeLimit = 6,
}) {
  if (graph.nodes.isEmpty) return const <ConceptNode>[];
  final safeLimit = nodeLimit.clamp(2, 8).toInt();
  final nodesById = {for (final node in graph.nodes) node.id: node};
  final scores = _scoreDerivedBookGraphNodes(graph);
  final coreView = _coreDerivedBookGraphView(
    graph,
    nodeLimit: safeLimit + 2,
  );
  final centerNode = nodesById[coreView.centerNodeId] ?? coreView.nodes.first;
  final selected = <String, ConceptNode>{centerNode.id: centerNode};

  final incidentEdges = graph.edges
      .where(
        (edge) =>
            edge.sourceNodeId == centerNode.id ||
            edge.targetNodeId == centerNode.id,
      )
      .toList(growable: false)
    ..sort((a, b) {
      final scoreCompare =
          _readingPathEdgeScore(b).compareTo(_readingPathEdgeScore(a));
      if (scoreCompare != 0) return scoreCompare;
      return a.id.compareTo(b.id);
    });

  for (final edge in incidentEdges) {
    if (selected.length >= safeLimit) break;
    final neighborId = edge.sourceNodeId == centerNode.id
        ? edge.targetNodeId
        : edge.sourceNodeId;
    final neighbor = nodesById[neighborId];
    if (neighbor != null) selected[neighbor.id] = neighbor;
  }

  final connectedNodeIds = <String>{
    for (final edge in graph.edges) ...[edge.sourceNodeId, edge.targetNodeId],
  };
  final remainingCoreNodes = coreView.nodes
      .where(
        (node) =>
            !selected.containsKey(node.id) &&
            connectedNodeIds.contains(node.id),
      )
      .toList(growable: false)
    ..sort((a, b) {
      final scoreCompare = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
      if (scoreCompare != 0) return scoreCompare;
      return a.label.compareTo(b.label);
    });
  for (final node in remainingCoreNodes) {
    if (selected.length >= safeLimit) break;
    selected[node.id] = node;
  }

  if (selected.length == 1 && graph.edges.isEmpty) {
    for (final node in coreView.nodes) {
      if (selected.length >= safeLimit) break;
      selected[node.id] = node;
    }
  }

  return selected.values.toList(growable: false);
}

double _readingPathEdgeScore(ConceptEdge edge) {
  final confidence = (edge.confidence ?? 0.5).clamp(0.0, 1.0).toDouble();
  final evidenceCount =
      edge.evidenceRefs.where((ref) => ref.hasEvidence).length;
  return confidence * 10 + evidenceCount * 3;
}

Map<String, double> _scoreDerivedBookGraphNodes(
  DerivedBookConceptGraphSnapshot graph,
) {
  final scores = <String, double>{
    for (final node in graph.nodes)
      node.id: node.sourceRefs.where((ref) => ref.hasEvidence).length * 4.0,
  };
  for (final edge in graph.edges) {
    final edgeWeight = 10.0 + ((edge.confidence ?? 0.5).clamp(0.0, 1.0) * 6.0);
    final evidenceWeight =
        edge.evidenceRefs.where((ref) => ref.hasEvidence).length * 2.0;
    scores[edge.sourceNodeId] =
        (scores[edge.sourceNodeId] ?? 0) + edgeWeight + evidenceWeight;
    scores[edge.targetNodeId] =
        (scores[edge.targetNodeId] ?? 0) + edgeWeight + evidenceWeight;
  }
  return scores;
}

class _DerivedBookReadingPath extends StatelessWidget {
  const _DerivedBookReadingPath({
    required this.graph,
    required this.nodes,
    required this.compact,
    required this.onNodeSelected,
    required this.onEdgeSelected,
  });

  final DerivedBookConceptGraphSnapshot graph;
  final List<ConceptNode> nodes;
  final bool compact;
  final ValueChanged<ConceptNode> onNodeSelected;
  final ValueChanged<ConceptEdge> onEdgeSelected;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final evidenceCount = _readingPathEvidenceCount(graph, nodes);
    final pathNodes = compact ? nodes.take(4).toList(growable: false) : nodes;
    final pathChips = <Widget>[
      for (var index = 0; index < pathNodes.length; index += 1) ...[
        ActionChip(
          key: ValueKey('full-book-reading-path-node-${pathNodes[index].id}'),
          avatar: CircleAvatar(
            radius: 10,
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          label: Text(pathNodes[index].label),
          onPressed: () => onNodeSelected(pathNodes[index]),
        ),
        if (index < pathNodes.length - 1)
          ..._readingPathEdgeChips(
            context,
            edge: _readingPathEdgeBetween(
              graph,
              pathNodes[index].id,
              pathNodes[index + 1].id,
            ),
            onEdgeSelected: onEdgeSelected,
          ),
      ],
    ];
    if (compact) {
      return Wrap(
        key: const ValueKey('full-book-reading-path'),
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.alt_route_outlined, size: 18),
          Text(
            zh ? '导读路径' : 'Reading path',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _TinyChip(label: zh ? '从这里开始' : 'Start here'),
          ...pathChips,
        ],
      );
    }
    return Column(
      key: const ValueKey('full-book-reading-path'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.alt_route_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                zh ? '导读路径' : 'Reading path',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _TinyChip(label: zh ? '从这里开始' : 'Start here'),
            const SizedBox(width: 6),
            _TinyChip(
              label: zh
                  ? '$evidenceCount 条证据'
                  : evidenceCount == 1
                      ? '1 evidence'
                      : '$evidenceCount evidence',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pathChips,
        ),
      ],
    );
  }
}

List<Widget> _readingPathEdgeChips(
  BuildContext context, {
  required ConceptEdge? edge,
  required ValueChanged<ConceptEdge> onEdgeSelected,
}) {
  if (edge == null) return const <Widget>[];
  return [
    ActionChip(
      key: ValueKey('full-book-reading-path-edge-${edge.id}'),
      avatar: const Icon(Icons.link, size: 16),
      label: Text(_edgeDisplayLabel(edge)),
      onPressed: () => onEdgeSelected(edge),
    ),
    _TinyChip(label: _readingPathEdgeEvidenceLabel(context, edge)),
  ];
}

ConceptEdge? _readingPathEdgeBetween(
  DerivedBookConceptGraphSnapshot graph,
  String firstNodeId,
  String secondNodeId,
) {
  final candidates = graph.edges
      .where(
        (edge) =>
            edge.sourceNodeId == firstNodeId &&
                edge.targetNodeId == secondNodeId ||
            edge.sourceNodeId == secondNodeId &&
                edge.targetNodeId == firstNodeId,
      )
      .toList(growable: false);
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final scoreCompare =
        _readingPathEdgeScore(b).compareTo(_readingPathEdgeScore(a));
    if (scoreCompare != 0) return scoreCompare;
    return a.id.compareTo(b.id);
  });
  return candidates.first;
}

String _readingPathEdgeEvidenceLabel(BuildContext context, ConceptEdge edge) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final evidenceCount =
      edge.evidenceRefs.where((ref) => ref.hasEvidence).length;
  if (zh) return '$evidenceCount 条证据';
  return evidenceCount == 1 ? '1 evidence ref' : '$evidenceCount evidence refs';
}

int _readingPathEvidenceCount(
  DerivedBookConceptGraphSnapshot graph,
  List<ConceptNode> nodes,
) {
  final nodeIds = nodes.map((node) => node.id).toSet();
  final nodeEvidence = nodes.fold<int>(
    0,
    (count, node) =>
        count + node.sourceRefs.where((ref) => ref.hasEvidence).length,
  );
  final edgeEvidence = graph.edges
      .where(
        (edge) =>
            nodeIds.contains(edge.sourceNodeId) &&
            nodeIds.contains(edge.targetNodeId),
      )
      .fold<int>(
        0,
        (count, edge) =>
            count + edge.evidenceRefs.where((ref) => ref.hasEvidence).length,
      );
  return nodeEvidence + edgeEvidence;
}

class _DerivedBookMapSummary extends StatelessWidget {
  const _DerivedBookMapSummary({
    required this.graph,
    required this.coreView,
    required this.compact,
    required this.focusedBySelection,
    required this.onCoreNodeSelected,
  });

  final DerivedBookConceptGraphSnapshot graph;
  final _DerivedBookGraphCoreView coreView;
  final bool compact;
  final bool focusedBySelection;
  final ValueChanged<ConceptNode> onCoreNodeSelected;

  @override
  Widget build(BuildContext context) {
    if (graph.isEmpty || coreView.nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final coreNode = coreView.nodes.firstWhere(
      (node) => node.id == coreView.centerNodeId,
      orElse: () => coreView.nodes.first,
    );
    final keyNodeIds = <String>{
      coreNode.id,
      for (final edge in coreView.edges) ...[
        edge.sourceNodeId,
        edge.targetNodeId,
      ],
    };
    final keyConceptCount =
        coreView.nodes.where((node) => keyNodeIds.contains(node.id)).length;
    final evidenceCount = _bookMapEvidenceCount(
      coreView,
      keyNodeIds: keyNodeIds,
    );
    final evidenceSections = _bookMapEvidenceSections(
      coreView,
      keyNodeIds: keyNodeIds,
    );
    final summaryChildren = <Widget>[
      const Icon(Icons.map_outlined, size: 18),
      Text(
        zh ? '本书地图' : 'Book map',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      _TinyChip(label: zh ? '核心主题' : 'Core theme'),
      if (focusedBySelection)
        _TinyChip(label: zh ? '按选中文本聚焦' : 'Focused by selection'),
      ActionChip(
        key: ValueKey('full-book-map-core-node-${coreNode.id}'),
        avatar: Icon(_nodeIcon(coreNode.type), size: 16),
        label: Text(coreNode.label),
        onPressed: () => onCoreNodeSelected(coreNode),
      ),
      _TinyChip(
        label: zh
            ? '$keyConceptCount 个关键概念'
            : keyConceptCount == 1
                ? '1 key concept'
                : '$keyConceptCount key concepts',
      ),
      _TinyChip(
        label: zh
            ? '${coreView.edges.length} 条主干关系'
            : coreView.edges.length == 1
                ? '1 backbone relation'
                : '${coreView.edges.length} backbone relations',
      ),
      _TinyChip(
        label: zh
            ? '$evidenceCount 条证据'
            : evidenceCount == 1
                ? '1 evidence ref'
                : '$evidenceCount evidence refs',
      ),
      if (evidenceSections.isNotEmpty)
        _TinyChip(label: zh ? '证据章节' : 'Evidence sections'),
      for (final section in evidenceSections.take(2))
        ActionChip(
          key: ValueKey('full-book-map-section-${section.label}'),
          label: Text(section.label),
          onPressed: () => onCoreNodeSelected(section.node),
        ),
    ];
    if (compact) {
      return SingleChildScrollView(
        key: const ValueKey('full-book-map-summary'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < summaryChildren.length; index += 1) ...[
              if (index > 0) const SizedBox(width: 8),
              summaryChildren[index],
            ],
          ],
        ),
      );
    }
    return Column(
      key: const ValueKey('full-book-map-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.map_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                zh ? '本书地图' : 'Book map',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _TinyChip(label: zh ? '派生预览' : 'Derived preview'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: summaryChildren.skip(2).take(2).toList(growable: false),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: summaryChildren.skip(4).toList(growable: false),
        ),
      ],
    );
  }
}

class _BookMapEvidenceSection {
  const _BookMapEvidenceSection({
    required this.label,
    required this.node,
  });

  final String label;
  final ConceptNode node;
}

List<_BookMapEvidenceSection> _bookMapEvidenceSections(
  _DerivedBookGraphCoreView coreView, {
  required Set<String> keyNodeIds,
  int limit = 3,
}) {
  final sections = <_BookMapEvidenceSection>[];
  final seen = <String>{};
  for (final node in coreView.nodes) {
    if (!keyNodeIds.contains(node.id)) continue;
    for (final sourceRef in node.sourceRefs) {
      final label = _sourceRefSectionLabel(sourceRef);
      if (label == null || !seen.add(label)) continue;
      sections.add(_BookMapEvidenceSection(label: label, node: node));
      if (sections.length >= limit) return sections;
    }
  }
  return sections;
}

String? _sourceRefSectionLabel(SourceRef sourceRef) {
  final title = sourceRef.sourceTitle?.trim();
  final location = sourceRef.locationLabel?.trim();
  if (title != null && title.isNotEmpty) {
    if (location != null && location.isNotEmpty) {
      return '$title / $location';
    }
    return title;
  }
  if (location != null && location.isNotEmpty) return location;
  final href = sourceRef.href?.trim();
  if (href != null && href.isNotEmpty) return href;
  return null;
}

int _bookMapEvidenceCount(
  _DerivedBookGraphCoreView coreView, {
  required Set<String> keyNodeIds,
}) {
  final nodeEvidence =
      coreView.nodes.where((node) => keyNodeIds.contains(node.id)).fold<int>(
            0,
            (count, node) =>
                count + node.sourceRefs.where((ref) => ref.hasEvidence).length,
          );
  final edgeEvidence = coreView.edges
      .where(
        (edge) =>
            keyNodeIds.contains(edge.sourceNodeId) &&
            keyNodeIds.contains(edge.targetNodeId),
      )
      .fold<int>(
        0,
        (count, edge) =>
            count + edge.evidenceRefs.where((ref) => ref.hasEvidence).length,
      );
  return nodeEvidence + edgeEvidence;
}

class _ConceptGraphCanvas extends StatelessWidget {
  const _ConceptGraphCanvas({
    this.paintKey = const ValueKey('concept-graph-visual-map'),
    this.height = 180,
    required this.nodes,
    required this.edges,
    required this.centerNodeId,
    this.onNodeSelected,
    this.onEdgeSelected,
  });

  final Key paintKey;
  final double height;
  final List<ConceptNode> nodes;
  final List<ConceptEdge> edges;
  final String centerNodeId;
  final ValueChanged<ConceptNode>? onNodeSelected;
  final ValueChanged<ConceptEdge>? onEdgeSelected;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final canvas = SizedBox(
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
    final onSelected = onNodeSelected;
    final onEdgeSelected = this.onEdgeSelected;
    if (onSelected == null && onEdgeSelected == null) return canvas;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        final size = box?.size;
        if (size == null || size.isEmpty) return;
        if (onSelected != null) {
          final node = _hitTestConceptGraphNode(
            details.localPosition,
            size,
            nodes,
            centerNodeId,
          );
          if (node != null) {
            onSelected(node);
            return;
          }
        }
        if (onEdgeSelected != null) {
          final edge = _hitTestConceptGraphEdge(
            details.localPosition,
            size,
            nodes,
            edges,
            centerNodeId,
          );
          if (edge != null) onEdgeSelected(edge);
        }
      },
      child: canvas,
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

    final positions = _layoutConceptGraphNodes(size, nodes, centerNodeId);
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

Map<String, Offset> _layoutConceptGraphNodes(
  Size size,
  List<ConceptNode> nodes,
  String centerNodeId,
) {
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
  final minX = math.min(34.0, size.width / 2);
  final maxX = math.max(minX, size.width - 34.0);
  final minY = math.min(34.0, size.height / 2);
  final maxY = math.max(minY, size.height - 42.0);
  for (var i = 0; i < others.length; i++) {
    final angle = -math.pi / 2 + (math.pi * 2 * i / others.length);
    final x = center.dx + math.cos(angle) * ringRadius;
    final y = center.dy + math.sin(angle) * ringRadius;
    positions[others[i].id] = Offset(
      x.clamp(minX, maxX).toDouble(),
      y.clamp(minY, maxY).toDouble(),
    );
  }
  return positions;
}

ConceptNode? _hitTestConceptGraphNode(
  Offset localPosition,
  Size size,
  List<ConceptNode> nodes,
  String centerNodeId,
) {
  final positions = _layoutConceptGraphNodes(size, nodes, centerNodeId);
  ConceptNode? closest;
  var closestDistance = double.infinity;
  for (final node in nodes) {
    final center = positions[node.id];
    if (center == null) continue;
    final distance = (localPosition - center).distance;
    final hitRadius = node.id == centerNodeId ? 30.0 : 25.0;
    if (distance <= hitRadius && distance < closestDistance) {
      closest = node;
      closestDistance = distance;
    }
  }
  return closest;
}

ConceptEdge? _hitTestConceptGraphEdge(
  Offset localPosition,
  Size size,
  List<ConceptNode> nodes,
  List<ConceptEdge> edges,
  String centerNodeId,
) {
  final positions = _layoutConceptGraphNodes(size, nodes, centerNodeId);
  ConceptEdge? closest;
  var closestDistance = double.infinity;
  for (final edge in edges) {
    final source = positions[edge.sourceNodeId];
    final target = positions[edge.targetNodeId];
    if (source == null || target == null) continue;
    final distance = _distanceToSegment(localPosition, source, target);
    if (distance <= 12 && distance < closestDistance) {
      closest = edge;
      closestDistance = distance;
    }
  }
  return closest;
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) return (point - start).distance;
  final relative = point - start;
  final projection =
      (relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared;
  final t = projection.clamp(0.0, 1.0).toDouble();
  final closest = Offset(
    start.dx + segment.dx * t,
    start.dy + segment.dy * t,
  );
  return (point - closest).distance;
}

class _MapNodePill extends StatelessWidget {
  const _MapNodePill({
    required this.node,
    this.isCenter = false,
    this.onTap,
  });

  final ConceptNode node;
  final bool isCenter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final pill = ConstrainedBox(
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
    final onTap = this.onTap;
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: pill,
    );
  }
}

class _LocalGraphEdgeSummary extends StatelessWidget {
  const _LocalGraphEdgeSummary({
    required this.edge,
    required this.nodesById,
    this.onTap,
  });

  final ConceptEdge edge;
  final Map<String, ConceptNode> nodesById;
  final VoidCallback? onTap;

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
      onTap: onTap,
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
        ? draftResult.reviewItems.isNotEmpty
            ? l10n.knowledgeCardAddedToReviewInbox
            : l10n.conceptGraphAddedToMyGraph
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
        : cardResult.inserted
            ? l10n.knowledgeCardSavedInline
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
