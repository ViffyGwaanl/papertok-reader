import 'dart:math';

import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

class StatisticsDashboard extends ConsumerWidget {
  const StatisticsDashboard({super.key, required this.snapshot});

  final StatisticsDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final workingTiles = tilesState.workingTiles;
    final availableTiles = notifier.availableTiles;

    void showAddTileSheet() {
      if (availableTiles.isEmpty) return;
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableTiles.length,
              itemBuilder: (context, index) {
                final type = availableTiles[index];
                final metadata = dashboardTileRegistry[type]!.metadata;
                return ListTile(
                  leading: Icon(metadata.icon),
                  title: Text(metadata.title),
                  subtitle: Text(metadata.description),
                  onTap: () {
                    Navigator.pop(context);
                    notifier.addTile(type);
                  },
                );
              },
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Dashboard', // TODO(l10n)
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (tilesState.isEditing)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: notifier.discardChanges,
                    child: const Text('Discard'), // TODO(l10n)
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: notifier.saveLayout,
                    icon: const Icon(Icons.save),
                    label: const Text('Save layout'), // TODO(l10n)
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Long press a card to rearrange.', // TODO(l10n)
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600])),
            const Spacer(),
            TextButton.icon(
              onPressed: availableTiles.isEmpty ? null : showAddTileSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add card'), // TODO(l10n)
            ),
          ],
        ),
        const SizedBox(height: 12),
        workingTiles.isEmpty
            ? _EmptyDashboardState(onAddPressed: showAddTileSheet)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisUnits =
                      _calculateColumnUnits(constraints.maxWidth);
                  return StaggeredReorderableView.customer(
                    columnNum: crossAxisUnits,
                    spacing: 10,
                    canDrag: true,
                    children: _buildReorderableItems(
                      context,
                      snapshot,
                      workingTiles,
                      crossAxisUnits,
                      notifier.removeTile,
                    ),
                    onReorder: notifier.reorder,
                    fixedCellHeight: 90,
                  );
                },
              ),
      ],
    );
  }

  List<ReorderableItem> _buildReorderableItems(
    BuildContext context,
    StatisticsDashboardSnapshot snapshot,
    List<StatisticsDashboardTileType> workingTiles,
    int columnUnits,
    void Function(StatisticsDashboardTileType) onRemove,
  ) {
    return workingTiles
        .map(
          (type) => dashboardTileRegistry[type]!.buildReorderableItem(
            context: context,
            snapshot: snapshot,
            onRemove: () => onRemove(type),
            columnUnits: columnUnits,
            baseTileHeight: kDashboardTileBaseHeight,
          ),
        )
        .toList(growable: false);
  }

  int _calculateColumnUnits(double width) {
    return max(4, (width ~/ 200) * 2);
  }
}

class _EmptyDashboardState extends StatelessWidget {
  const _EmptyDashboardState({this.onAddPressed});

  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
            'No cards yet. Tap “Add card” to get started.'), // TODO(l10n)
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPressed,
          icon: const Icon(Icons.add),
          label: const Text('Add card'), // TODO(l10n)
        ),
      ],
    );
  }
}
