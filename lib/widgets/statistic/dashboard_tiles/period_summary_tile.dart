import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PeriodSummaryTile extends ConsumerWidget {
  const PeriodSummaryTile({
    super.key,
    required this.snapshot,
    required this.metadata,
  });

  final StatisticsDashboardSnapshot snapshot;
  final StatisticsDashboardTileMetadata metadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticData = ref.watch(statisticDataProvider);
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

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
            Text('$formatted of reading',
                style: theme.textTheme.headlineSmall), // TODO(l10n)
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
  }
}
