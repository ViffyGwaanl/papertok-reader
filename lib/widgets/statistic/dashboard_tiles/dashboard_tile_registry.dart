import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/library_totals_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/period_summary_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/top_book_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/total_time_tile.dart';

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
  StatisticsDashboardTileType.periodSummary,
  StatisticsDashboardTileType.libraryTotals,
  StatisticsDashboardTileType.topBook,
];

const Map<StatisticsDashboardTileType, StatisticsDashboardTileBase>
    dashboardTileRegistry = {
  StatisticsDashboardTileType.totalTime: TotalTimeTile(),
  StatisticsDashboardTileType.periodSummary: PeriodSummaryTile(),
  StatisticsDashboardTileType.libraryTotals: LibraryTotalsTile(),
  StatisticsDashboardTileType.topBook: TopBookTile(),
};
