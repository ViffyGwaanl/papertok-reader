import 'package:anx_reader/providers/reading_duration_trend_provider.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingDurationTrendTile extends StatisticsDashboardTileBase {
  const ReadingDurationTrendTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.readingDurationTrend,
        title: 'Pace tracker', // TODO(l10n)
        description:
            'Cumulative reading time across the last 7 and 30 days.', // TODO(l10n)
        columnSpan: 4,
        rowSpan: 2,
        icon: Icons.timeline,
      );

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingDurationTrendProvider);
    return AsyncSkeletonWrapper<ReadingDurationTrendData>(
      asyncValue: asyncValue,
      mock: ReadingDurationTrendData.mock(),
      builder: (data) => _ReadingDurationTrendContent(data: data),
    );
  }
}

class _ReadingDurationTrendContent extends StatefulWidget {
  const _ReadingDurationTrendContent({required this.data});

  final ReadingDurationTrendData data;

  @override
  State<_ReadingDurationTrendContent> createState() =>
      _ReadingDurationTrendContentState();
}

class _ReadingDurationTrendContentState
    extends State<_ReadingDurationTrendContent> {
  int selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final series = selectedDays == 7
        ? widget.data.lastSevenDays
        : widget.data.lastThirtyDays;

    final theme = Theme.of(context);
    final totalLabel = convertSeconds(series.totalSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnxSegmentedButton<int>(
          segments: const [
            SegmentButtonItem(value: 7, label: '7d'),
            SegmentButtonItem(value: 30, label: '30d'),
          ],
          selected: {selectedDays},
          onSelectionChanged: (selection) {
            setState(() {
              selectedDays = selection.first;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          '$totalLabel logged', // TODO(l10n)
          style: theme.textTheme.bodyMedium,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _TrendChart(series: series),
          ),
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
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= series.labels.length) {
                  return const SizedBox.shrink();
                }
                final label = series.labels[index];
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            // tooltipBgColor: theme.colorScheme.surfaceVariant,
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final index = spot.x.toInt();
                final seconds = series.cumulativeSeconds[index];
                return LineTooltipItem(
                  convertSeconds(seconds),
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
}
