import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/deeplink/paperreader_deeplink_handler.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class ConceptGraphExplorerPage extends ConsumerStatefulWidget {
  const ConceptGraphExplorerPage({
    super.key,
    this.initialQuery,
  });

  final String? initialQuery;

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
          _IntegrityBanner(state: state),
          Expanded(
            child: state.nodes.when(
              data: (nodes) => _ConceptGraphBody(
                nodes: nodes,
                state: state,
                initialQuery: initialQuery == null || initialQuery.isEmpty
                    ? null
                    : initialQuery,
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
  });

  final List<ConceptNode> nodes;
  final ConceptGraphExplorerState state;
  final String? initialQuery;

  @override
  Widget build(BuildContext context) {
    final visibleNodes = _filterNodesForQuery(nodes, initialQuery);
    if (visibleNodes.isEmpty) {
      return _EmptyGraph(
        selectionQuery: initialQuery,
        state: state,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          return Row(
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
              Expanded(child: _DossierPane(state: state)),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
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
            _DossierPane(state: state),
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
  const _DossierPane({required this.state});

  final ConceptGraphExplorerState state;

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
          child: _DossierContent(selection: selection, state: state),
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
  });

  final ConceptGraphExplorerSelection selection;
  final ConceptGraphExplorerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final dossier = selection.dossier;
    final firstIntent = _firstIntent([
      ...dossier.node.sourceRefs,
      ...dossier.appearances,
      ...dossier.supportingEvidence,
      ...dossier.contradictingEvidence,
    ]);

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
                ? null
                : () => PaperReaderDeepLinkHandler.handleIncomingUri(
                      ref,
                      firstIntent.toUri(),
                    ),
          ),
        ),
      ],
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
