import 'package:anx_reader/providers/reading_duration_trend_provider.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/book_reading_chart.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class _BaseReadingDurationTile extends StatisticsDashboardTileBase {
  const _BaseReadingDurationTile({
    required this.type,
    required this.titleText,
    required this.descriptionText,
    required this.days,
  });

  final StatisticsDashboardTileType type;
  final String titleText;
  final String descriptionText;
  final int days;

  ReadingDurationSeries _selectSeries(ReadingDurationTrendData data) {
    return days == 7 ? data.lastSevenDays : data.lastThirtyDays;
  }

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerText(context, '$days ');
  }

  @override
  StatisticsDashboardTileMetadata get metadata =>
      StatisticsDashboardTileMetadata(
        type: type,
        title: titleText,
        description: descriptionText,
        columnSpan: 2,
        rowSpan: 1,
        icon: Icons.timeline,
      );

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingDurationTrendProvider);
    return AsyncSkeletonWrapper<ReadingDurationTrendData>(
      asyncValue: asyncValue,
      mock: ReadingDurationTrendData.mock(),
      builder: (data) => _ReadingDurationTileBody(
        series: _selectSeries(data),
      ),
    );
  }
}

class ReadingDurationLast7Tile extends _BaseReadingDurationTile {
  const ReadingDurationLast7Tile()
      : super(
          type: StatisticsDashboardTileType.readingDurationLast7,
          titleText: 'Past 7 days', // TODO(l10n)
          descriptionText:
              'Rolling 7-day cumulative reading time.', // TODO(l10n)
          days: 7,
        );
}

class ReadingDurationLast30Tile extends _BaseReadingDurationTile {
  const ReadingDurationLast30Tile()
      : super(
          type: StatisticsDashboardTileType.readingDurationLast30,
          titleText: 'Past 30 days', // TODO(l10n)
          descriptionText:
              'Rolling 30-day cumulative reading time.', // TODO(l10n)
          days: 30,
        );
}

class _ReadingDurationTileBody extends StatelessWidget {
  const _ReadingDurationTileBody({required this.series});

  final ReadingDurationSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalLabel = convertSeconds(series.totalSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          totalLabel, // TODO(l10n)
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BookReadingChart(
            cumulativeValues: series.cumulativeSeconds,
            dailySeconds: _dailyAmounts(series.cumulativeSeconds),
            dates: series.dates,
          ),
        ),
      ],
    );
  }

  List<int> _dailyAmounts(List<int> cumulative) {
    if (cumulative.isEmpty) return const [];
    final daily = <int>[];
    for (var i = 0; i < cumulative.length; i++) {
      if (i == 0) {
        daily.add(cumulative[i]);
      } else {
        final delta = cumulative[i] - cumulative[i - 1];
        daily.add(delta < 0 ? 0 : delta);
      }
    }
    return daily;
  }
}
