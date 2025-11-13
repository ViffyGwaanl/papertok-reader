import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PeriodSummaryTile extends StatisticsDashboardTileBase {
  const PeriodSummaryTile();

  @override
  get metadata => StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.periodSummary,
        title: 'Current period', // TODO(l10n)
        description: 'Highlights for the selected period below.', // TODO(l10n)
        columnSpan: 2,
        rowSpan: 1,
        icon: Icons.bar_chart_rounded,
      );

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    return Consumer(builder: (context, ref, _) {
      return AsyncSkeletonWrapper(
          asyncValue: ref.watch(statisticDataProvider),
          mock: StatisticDataModel.mock(),
          builder: (data) {
            final periodLabel = data.mode == ChartMode.week
                ? l10n.statisticWeek
                : data.mode == ChartMode.month
                    ? l10n.statisticMonth
                    : data.mode == ChartMode.year
                        ? l10n.statisticYear
                        : l10n.statisticAll;

            return Text(
              periodLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                  ),
            );
          });
    });
  }

  @override
  Widget buildContent(
    BuildContext context,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);

    return AsyncSkeletonWrapper(
        asyncValue: combineAsyncValues([
          ref.watch(statisticDataProvider),
          ref.watch(totalReadingTimeProvider),
        ]),
        mock: [
          StatisticDataModel.mock(),
          1,
        ],
        builder: (data) {
          final statisticData = data[0] as StatisticDataModel;
          final totalSeconds = data[1] as int;

          final periodSeconds = statisticData.mode == ChartMode.heatmap
              ? totalSeconds
              : statisticData.readingTime
                  .fold<int>(0, (sum, seconds) => sum + seconds);
          final formatted = convertSeconds(periodSeconds);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatted, style: theme.textTheme.headlineSmall),
              Text(
                  '${(periodSeconds / totalSeconds * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.labelMedium),
              const Spacer(),
              LinearProgressIndicator(
                value: periodSeconds == 0
                    ? 0
                    : (periodSeconds / totalSeconds).clamp(0, 1).toDouble(),
                minHeight: 6,
              ),
            ],
          );
        });
  }
}
