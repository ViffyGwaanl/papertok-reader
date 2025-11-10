import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

/// Base class for all statistics dashboard tiles.
abstract class StatisticsDashboardTileBase {
  const StatisticsDashboardTileBase(this.metadata);

  final StatisticsDashboardTileMetadata metadata;

  StatisticsDashboardTileType get type => metadata.type;

  /// Builds the tile body.
  Widget buildContent(
    BuildContext context,
    StatisticsDashboardSnapshot snapshot,
  );

  /// Returns the [ReorderableItem] used by the reorderable grid.
  ReorderableItem buildReorderableItem({
    required BuildContext context,
    required StatisticsDashboardSnapshot snapshot,
    required VoidCallback? onRemove,
    required int columnUnits,
    required double baseTileHeight,
  }) {
    final span = metadata.columnSpan.clamp(1, columnUnits);

    return ReorderableItem(
      trackingNumber: type.index,
      id: type.name,
      crossAxisCellCount: span,
      mainAxisCellCount: metadata.rowSpan,
      child: DashboardTileShell(
        tileType: type,
        onRemove: onRemove,
        child: buildContent(context, snapshot),
      ),
      placeholder: DashboardTileShell(
        tileType: type,
        onRemove: null,
        child: buildContent(context, snapshot),
      ),
    );
  }
}

class DashboardTileShell extends ConsumerWidget {
  const DashboardTileShell({
    super.key,
    required this.child,
    required this.tileType,
    this.onRemove,
  });

  final Widget child;
  final StatisticsDashboardTileType tileType;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardTilesProvider);
    final showRemoveButton =
        state.isEditing && state.workingTiles.length > 1 && onRemove != null;
    return SizedBox.expand(
      child: FilledContainer(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(6),
        radius: 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (showRemoveButton)
              Positioned(
                top: -8,
                right: -8,
                child: IconButton.filledTonal(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove card', // TODO(l10n)
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
