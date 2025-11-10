import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
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
    required bool canRemove,
    required VoidCallback? onRemove,
    required int columnUnits,
    required double baseTileHeight,
  }) {
    final span =  metadata.columnSpan;

    DashboardTileShell buildShell({required bool includeRemoveButton}) {
      return DashboardTileShell(
        child: buildContent(context, snapshot),
        showRemoveButton: includeRemoveButton && canRemove && onRemove != null,
        onRemove: includeRemoveButton ? onRemove : null,
      );
    }

    return ReorderableItem(
      trackingNumber: type.index,
      id: type.name,
      crossAxisCellCount: span,
      mainAxisCellCount: metadata.rowSpan,
      child: buildShell(includeRemoveButton: true),
      placeholder: Opacity(
        opacity: 0.25,
        child: buildShell(includeRemoveButton: false),
      ),
    );
  }
}

class DashboardTileShell extends StatelessWidget {
  const DashboardTileShell({
    super.key,
    required this.child,
    required this.showRemoveButton,
    this.onRemove,
  });

  final Widget child;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FilledContainer(
        padding: const EdgeInsets.all(6),
        radius: 12,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (showRemoveButton && onRemove != null)
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
