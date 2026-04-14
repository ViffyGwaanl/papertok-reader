import 'package:papertok_reader/enums/chart_mode.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/statistic_data_model.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:papertok_reader/providers/statistic_data.dart';
import 'package:papertok_reader/providers/total_reading_time.dart';
import 'package:papertok_reader/utils/date/convert_seconds.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PeriodSummaryTile extends StatisticsDashboardTileBase {
  const PeriodSummaryTile();

  @override
  get metadata => StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.periodSummary,
        title: l10nLocal.tilePeriodSummaryTitle,
        description: l10nLocal.tilePeriodSummaryDescription,
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
          builder: (data, _) {
            final periodLabel = data.mode == ChartMode.week
                ? l10n.statisticWeek
                : data.mode == ChartMode.month
                    ? l10n.statisticMonth
                    : data.mode == ChartMode.year
                        ? l10n.statisticYear
                        : l10n.statisticAll;

            return cornerText(
              context,
              periodLabel,
            );
          });
    });
  }

  @override
  Widget buildContent(
    BuildContext context,
    WidgetRef ref,
  ) {
    return AsyncSkeletonWrapper(
        asyncValue: combineAsyncValues([
          ref.watch(statisticDataProvider),
          ref.watch(totalReadingTimeProvider),
        ]),
        mock: [
          StatisticDataModel.mock(),
          1,
        ],
        builder: (data, _) {
          final statisticData = data[0] as StatisticDataModel;
          final totalSeconds = data[1] as int;

          final periodSeconds = statisticData.mode == ChartMode.heatmap
              ? totalSeconds
              : statisticData.readingTime
                  .fold<int>(0, (sum, seconds) => sum + seconds);
          final formatted = convertSeconds(periodSeconds);
          final percentText = totalSeconds == 0
              ? '0.0%'
              : '${(periodSeconds / totalSeconds * 100).toStringAsFixed(1)}%';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatted,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ClaudePalette.fg(context),
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      percentText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ClaudePalette.accent(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: periodSeconds == 0 || totalSeconds == 0
                      ? 0
                      : (periodSeconds / totalSeconds).clamp(0, 1).toDouble(),
                  minHeight: 4,
                  color: ClaudePalette.accent(context),
                  backgroundColor: ClaudePalette.divider(context),
                ),
              ),
            ],
          );
        });
  }
}
