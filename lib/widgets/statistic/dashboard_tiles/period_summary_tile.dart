import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PeriodSummaryTile extends StatisticsDashboardTileBase {
  const PeriodSummaryTile()
      : super(const StatisticsDashboardTileMetadata(
          type: StatisticsDashboardTileType.periodSummary,
          title: 'Current period', // TODO(l10n)
          description:
              'Highlights for the selected period below.', // TODO(l10n)
          columnSpan: 2,
          rowSpan: 1,
          icon: Icons.bar_chart_rounded,
        ));

  @override
  Widget buildContent(
    BuildContext context,
    StatisticsDashboardSnapshot _,
  ) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Consumer(
      builder: (context, ref, __) {
        final statisticData = ref.watch(statisticDataProvider);
        return statisticData.when(
          data: (data) {
            final totalSeconds =
                data.readingTime.fold<int>(0, (sum, seconds) => sum + seconds);
            final formatted = convertSeconds(totalSeconds);
            final periodLabel = data.mode == ChartMode.week
                ? l10n.statisticWeek
                : data.mode == ChartMode.month
                    ? l10n.statisticMonth
                    : l10n.statisticYear;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metadata.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  periodLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text('$formatted of reading', // TODO(l10n)
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: totalSeconds == 0
                      ? 0
                      : (totalSeconds / 3600 / 10).clamp(0, 1).toDouble(),
                  minHeight: 6,
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
        );
      },
    );
  }
}
