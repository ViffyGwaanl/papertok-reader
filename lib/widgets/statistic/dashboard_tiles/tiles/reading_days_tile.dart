import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/widgets/mini_metric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingDaysTile extends StatisticsDashboardTileBase {
  const ReadingDaysTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.readingDaysTotal,
        title: 'Active days', // TODO(l10n)
        description: 'Number of days you opened a book.', // TODO(l10n)
        columnSpan: 1,
        rowSpan: 1,
        icon: Icons.calendar_today_outlined,
      );

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue =
        ref.watch(StaticticsSummaryValueProvider(StatisticType.totalDates));

    return AsyncSkeletonWrapper<int>(
      asyncValue: asyncValue,
      mock: 28,
      builder: (count) => DashboardMiniMetric(
        value: count,
        label: 'days', // TODO(l10n)
        icon: metadata.icon,
      ),
    );
  }
}
