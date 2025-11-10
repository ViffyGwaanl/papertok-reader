import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TotalTimeTile extends ConsumerWidget {
  const TotalTimeTile({
    super.key,
    required this.snapshot,
    required this.metadata,
  });

  final StatisticsDashboardSnapshot snapshot;
  final StatisticsDashboardTileMetadata metadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              spacing: 12,
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
          value,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
