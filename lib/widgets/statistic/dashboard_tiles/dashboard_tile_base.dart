import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_detail_view.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:heroine/heroine.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

/// Base class for all statistics dashboard tiles.
abstract class StatisticsDashboardTileBase {
  const StatisticsDashboardTileBase(this.metadata);

  final StatisticsDashboardTileMetadata metadata;

  StatisticsDashboardTileType get type => metadata.type;

  /// Builds the tile body with access to BuildContext and WidgetRef.
  Widget buildContent(BuildContext context, WidgetRef ref);

  /// Called when the tile is removed from the dashboard.
  /// Override this method to perform cleanup or additional actions.
  void onRemove(BuildContext context, WidgetRef ref) {}

  /// Builds an optional icon widget for the tile.
  /// Override this method to provide a custom icon.
  Widget buildCorner(BuildContext context, WidgetRef ref) => SizedBox.shrink();

  Widget cornerIcon(BuildContext context, IconData iconData) {
    return Icon(
      iconData,
      size: 90,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  String get title => '';

  /// Returns the [ReorderableItem] used by the reorderable grid.
  ReorderableItem buildReorderableItem({required BuildContext context}) {
    return ReorderableItem(
      trackingNumber: type.index,
      id: type.name,
      crossAxisCellCount: metadata.columnSpan,
      mainAxisCellCount: metadata.rowSpan,
      child: DashboardTileShell(
        tileType: type,
        tile: this,
        buildContent: buildContent,
      ),
      placeholder: Opacity(
        opacity: 0.5,
        child: DashboardTileShell(
          tileType: type,
          tile: this,
          buildContent: buildContent,
        ),
      ),
    );
  }
}

class DashboardTileShell extends ConsumerWidget {
  const DashboardTileShell({
    super.key,
    required this.buildContent,
    required this.tileType,
    required this.tile,
  });

  final Widget Function(BuildContext context, WidgetRef ref) buildContent;
  final StatisticsDashboardTileType tileType;
  final StatisticsDashboardTileBase tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardTilesProvider);
    final showRemoveButton = state.isEditing && state.workingTiles.length > 1;

    final notifier = ref.read(dashboardTilesProvider.notifier);
    final heroTag = 'dashboard_tile_${tileType.name}';

    return Heroine(
      tag: heroTag,
      flightShuttleBuilder: const FlipShuttleBuilder(
        axis: Axis.vertical,
        halfFlips: 1,
      ),
      motion: Motion.bouncySpring(
        snapToEnd: true,
        duration: const Duration(milliseconds: 500),
      ),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              opaque: false,
              pageBuilder: (context, animation, secondaryAnimation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    return DashboardTileDetailView(
                      tile: tile,
                      heroTag: heroTag,
                      animationValue: animation.value,
                    );
                  },
                );
              },
            ),
          );
        },
        child: Stack(
          children: [
            FilledContainer(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(6),
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (tile.title.isNotEmpty)
                    Text(
                      tile.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  Expanded(
                    child: buildContent(context, ref),
                  ),
                ],
              ),
            ),
            if (showRemoveButton)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove card', // TODO(l10n)
                  onPressed: () {
                    notifier.removeTile(tileType);
                    tile.onRemove(context, ref);
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            Positioned(
              bottom: -20,
              right: -20,
              child: Opacity(
                opacity: 0.1,
                child: Transform.rotate(
                  angle: -0.2,
                  child: tile.buildCorner(context, ref),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
