import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/library_totals_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/period_summary_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/top_book_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/total_time_tile.dart';

const Map<StatisticsDashboardTileType, StatisticsDashboardTileBase>
    dashboardTileRegistry = {
  StatisticsDashboardTileType.totalTime: TotalTimeTile(),
  StatisticsDashboardTileType.libraryTotals: LibraryTotalsTile(),
  StatisticsDashboardTileType.periodSummary: PeriodSummaryTile(),
  StatisticsDashboardTileType.topBook: TopBookTile(),
};
