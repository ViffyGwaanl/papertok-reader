import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/reading_streak_provider.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingStreakTile extends StatisticsDashboardTileBase {
  const ReadingStreakTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.readingStreak,
      title: l10n.tileReadingStreakTitle,
      description: l10n.tileReadingStreakDescription,
      columnSpan: 2,
      rowSpan: 2,
      icon: Icons.local_fire_department_outlined,
    );
  }

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
      builder: (data, _) => _ReadingStreakContent(data: data),
    );
  }
}

class _ReadingStreakContent extends StatelessWidget {
  const _ReadingStreakContent({required this.data});

  final ReadingStreakData data;

  @override
  Widget build(BuildContext context) {
    final hasReadToday = _isSameDay(data.lastReadingDay, DateTime.now());
    final fireColor = hasReadToday
        ? MorandiPalette.clay(context)
        : ClaudePalette.tertiary(context);
    final l10n = L10n.of(context);
    final encouragement = hasReadToday
        ? l10n.tileReadingStreakEncouragementActive
        : l10n.tileReadingStreakEncouragementInactive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StreakColumn(
                icon: Icons.local_fire_department,
                iconColor: fireColor,
                value: data.currentStreak,
                label: l10n.tileReadingStreakBestLabel.isEmpty
                    ? 'CURRENT'
                    : 'CURRENT',
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: ClaudePalette.divider(context),
            ),
            Expanded(
              child: _StreakColumn(
                icon: Icons.emoji_events_outlined,
                iconColor: ClaudePalette.accent(context),
                value: data.longestStreak,
                label: 'BEST',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          encouragement,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: ClaudePalette.secondary(context),
            height: 1.35,
          ),
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

class _StreakColumn extends StatelessWidget {
  const _StreakColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.3,
              color: ClaudePalette.fg(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              color: ClaudePalette.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
