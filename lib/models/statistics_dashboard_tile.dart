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
