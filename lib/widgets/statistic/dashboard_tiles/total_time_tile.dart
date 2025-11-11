import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TotalTimeTile extends StatisticsDashboardTileBase {
  const TotalTimeTile()
      : super(const StatisticsDashboardTileMetadata(
          type: StatisticsDashboardTileType.totalTime,
          title: 'Lifetime reading', // TODO(l10n)
          description: 'Hours and minutes logged in Anx Reader.', // TODO(l10n)
          columnSpan: 2,
          rowSpan: 1,
          icon: Icons.timer_outlined,
        ));

  @override
  Widget buildContent(
    BuildContext context,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final totalReadingTime = ref.watch(totalReadingTimeProvider);
        return totalReadingTime.when(
          data: (seconds) {
            final hours = seconds ~/ 3600;
            final minutes = (seconds % 3600) ~/ 60;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metadata.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  runSpacing: 8,
                  children: [
                    _NumberBadge(
                      label: L10n.of(context).commonHours(hours),
                      value: hours.toString(),
                    ),
                    _NumberBadge(
                      label: L10n.of(context).commonMinutes(minutes),
                      value: minutes.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${Prefs().beginDate?.toString().substring(0, 10) ?? ''} '
                  '${L10n.of(context).statisticToPresent}',
                  style: Theme.of(context).textTheme.bodySmall,
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

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
