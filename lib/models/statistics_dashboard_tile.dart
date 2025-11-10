import 'package:flutter/foundation.dart';

/// Types of dashboard tiles that can appear in the statistics dashboard.
enum StatisticsDashboardTileType {
  totalTime,
  libraryTotals,
  periodSummary,
  topBook,
}

/// Default order for dashboard tiles when the user has not customized the layout.
const List<StatisticsDashboardTileType> defaultStatisticsDashboardTiles = [
  StatisticsDashboardTileType.totalTime,
  StatisticsDashboardTileType.libraryTotals,
  StatisticsDashboardTileType.periodSummary,
  StatisticsDashboardTileType.topBook,
];

/// Snapshot of the basic counters used by most tiles.
@immutable
class StatisticsDashboardSnapshot {
  const StatisticsDashboardSnapshot({
    required this.totalBooks,
    required this.totalDays,
    required this.totalNotes,
  });

  final int totalBooks;
  final int totalDays;
  final int totalNotes;
}
