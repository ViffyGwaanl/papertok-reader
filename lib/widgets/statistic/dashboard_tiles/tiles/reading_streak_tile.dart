import 'package:anx_reader/providers/reading_streak_provider.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingStreakTile extends StatisticsDashboardTileBase {
  const ReadingStreakTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.readingStreak,
        title: 'Reading streak', // TODO(l10n)
        description:
            'Track your current and best reading streaks for motivation.', // TODO(l10n)
        columnSpan: 2,
        rowSpan: 2,
        icon: Icons.local_fire_department_outlined,
      );

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingStreakProvider);
    return AsyncSkeletonWrapper<ReadingStreakData>(
      asyncValue: asyncValue,
      mock: const ReadingStreakData(
        currentStreak: 4,
        longestStreak: 12,
        lastReadingDay: null,
      ),
      builder: (data) => _ReadingStreakContent(data: data),
    );
  }
}

class _ReadingStreakContent extends StatelessWidget {
  const _ReadingStreakContent({required this.data});

  final ReadingStreakData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final fireColor =
        data.currentStreak > 0 ? primary : theme.colorScheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: fireColor),
            const SizedBox(width: 8),
            Text(
              '${data.currentStreak} day streak', // TODO(l10n)
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: fireColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          data.currentStreak > 0
              ? 'Don\'t break the chain!' // TODO(l10n)
              : 'Tap a book today to restart.', // TODO(l10n)
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatPill(
              label: 'Best streak', // TODO(l10n)
              value: '${data.longestStreak}d',
            ),
            _StatPill(
              label: 'Last read', // TODO(l10n)
              value: _lastReadLabel(data.lastReadingDay),
            ),
          ],
        ),
      ],
    );
  }

  String _lastReadLabel(DateTime? lastDay) {
    if (lastDay == null) return '--';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayOnly = DateTime(lastDay.year, lastDay.month, lastDay.day);
    final diff = today.difference(dayOnly).inDays;
    if (diff == 0) return 'Today'; // TODO(l10n)
    if (diff == 1) return 'Yesterday'; // TODO(l10n)
    return '$diff d ago'; // TODO(l10n)
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
