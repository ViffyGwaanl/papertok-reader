import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:papertok_reader/providers/total_reading_time.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TotalTimeTile extends StatisticsDashboardTileBase {
  const TotalTimeTile();

  @override
  get metadata => StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.totalTime,
        title: l10nLocal.tileTotalTimeTitle,
        description: l10nLocal.tileTotalTimeDescription,
        columnSpan: 2,
        rowSpan: 1,
        icon: Icons.timer_outlined,
      );

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, metadata.icon);
  }

  @override
  String get title => metadata.title;

  @override
  Widget buildContent(
    BuildContext context,
    WidgetRef ref,
  ) {
    final totalReadingTime = ref.watch(totalReadingTimeProvider);

    return AsyncSkeletonWrapper<int>(
      asyncValue: totalReadingTime,
      builder: (seconds, _) => _TotalTimeContent(
        seconds: seconds,
        metadata: metadata,
      ),
    );
  }
}

class _TotalTimeContent extends StatelessWidget {
  const _TotalTimeContent({
    required this.seconds,
    required this.metadata,
  });

  final int seconds;
  final StatisticsDashboardTileMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    final numberStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: ClaudePalette.fg(context),
      letterSpacing: -0.3,
      height: 1.05,
    );
    final unitStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: ClaudePalette.secondary(context),
      height: 1.05,
    );

    final hourLabel = L10n.of(context).commonHours(hours);
    final minuteLabel = L10n.of(context).commonMinutes(minutes);
    final hourSuffix = hourLabel.replaceAll(RegExp(r'[0-9]'), '').trim();
    final minuteSuffix = minuteLabel.replaceAll(RegExp(r'[0-9]'), '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: hours.toString(), style: numberStyle),
            if (hourSuffix.isNotEmpty)
              TextSpan(text: hourSuffix, style: unitStyle),
            const TextSpan(text: ' '),
            TextSpan(text: minutes.toString(), style: numberStyle),
            if (minuteSuffix.isNotEmpty)
              TextSpan(text: minuteSuffix, style: unitStyle),
          ]),
        ),
        const SizedBox(height: 4),
        Text(
          '${Prefs().beginDate?.toString().substring(0, 10) ?? ''} '
          '${L10n.of(context).statisticToPresent}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: ClaudePalette.tertiary(context),
          ),
        ),
      ],
    );
  }
}
