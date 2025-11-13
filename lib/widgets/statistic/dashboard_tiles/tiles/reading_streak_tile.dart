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
    final hasReadToday = _isSameDay(data.lastReadingDay, DateTime.now());
    final fireColor =
        hasReadToday ? theme.colorScheme.primary : theme.colorScheme.outline;
    final encouragement = hasReadToday
        ? 'You are on fire today.' // TODO(l10n)
        : 'Spend a few minutes reading today to keep the chain.'; // TODO(l10n)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: fireColor),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.currentStreak} day streak', // TODO(l10n)
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: fireColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StatPill(
              label: 'Best streak', // TODO(l10n)
              value: '${data.longestStreak}d',
            ),
          ],
        ),
        const Spacer(),
        Text(
          encouragement,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  bool _isSameDay(DateTime? date1, DateTime? date2) {
    if (date1 == null || date2 == null) return false;
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
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
