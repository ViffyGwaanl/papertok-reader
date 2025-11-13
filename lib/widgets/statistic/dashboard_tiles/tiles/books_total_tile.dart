import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/widgets/mini_metric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BooksTotalTile extends StatisticsDashboardTileBase {
  const BooksTotalTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.booksTotal,
        title: 'Books read', // TODO(l10n)
        description: 'Lifetime total number of finished books.', // TODO(l10n)
        columnSpan: 1,
        rowSpan: 1,
        icon: Icons.auto_stories_outlined,
      );

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue =
        ref.watch(StaticticsSummaryValueProvider(StatisticType.totalBooks));

    return AsyncSkeletonWrapper<int>(
        asyncValue: asyncValue,
        mock: 12,
        builder: (count) {
          return DashboardMiniMetric(
            value: count,
            label: 'books', // TODO(l10n)
            icon: metadata.icon,
          );
        });
  }
}
