import 'package:anx_reader/providers/reading_duration_trend_provider.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

abstract class _BaseReadingDurationTile extends StatisticsDashboardTileBase {
  const _BaseReadingDurationTile({
    required this.childType,
    required this.childTitle,
    required this.description,
    required this.days,
  });

  final StatisticsDashboardTileType childType;
  final String childTitle;
  final String description;
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
        type: childType,
        title: childTitle,
        description: description,
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
          childType: StatisticsDashboardTileType.readingDurationLast7,
          childTitle: 'Past 7 days', // TODO(l10n)
          description: 'Rolling 7-day cumulative reading time.', // TODO(l10n)
          days: 7,
        );
}

class ReadingDurationLast30Tile extends _BaseReadingDurationTile {
  const ReadingDurationLast30Tile()
      : super(
          childType: StatisticsDashboardTileType.readingDurationLast30,
          childTitle: 'Past 30 days', // TODO(l10n)
          description: 'Rolling 30-day cumulative reading time.', // TODO(l10n)
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
          child: _TrendChart(series: series),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.series});

  final ReadingDurationSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final maxY = (series.maxSeconds * 1.1).clamp(1, double.infinity);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (series.cumulativeSeconds.length - 1).toDouble(),
        minY: 0,
        maxY: maxY.toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              final formatter = DateFormat('M/d');
              return spots.map((spot) {
                final index = spot.x.toInt();
                final dateLabel = formatter.format(series.dates[index]);
                final daySeconds = _dailyAmount(index);
                return LineTooltipItem(
                  '$dateLabel · ${convertSeconds(daySeconds)}',
                  TextStyle(
                    color: primary,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              series.cumulativeSeconds.length,
              (index) => FlSpot(
                index.toDouble(),
                series.cumulativeSeconds[index].toDouble(),
              ),
            ),
            isCurved: true,
            color: primary,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  primary.withOpacity(0.3),
                  primary.withOpacity(0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _dailyAmount(int index) {
    if (index <= 0) {
      return series.cumulativeSeconds[index];
    }
    final value =
        series.cumulativeSeconds[index] - series.cumulativeSeconds[index - 1];
    return value < 0 ? 0 : value;
  }
}
