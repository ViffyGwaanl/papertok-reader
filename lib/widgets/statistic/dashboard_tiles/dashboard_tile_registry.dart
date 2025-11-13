import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/books_total_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/completion_progress_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/library_totals_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/notes_total_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/period_summary_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/random_highlight_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/reading_days_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/reading_duration_trend_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/reading_streak_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/top_book_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/total_time_tile.dart';

/// Types of dashboard tiles that can appear in the statistics dashboard.
enum StatisticsDashboardTileType {
  totalTime,
  libraryTotals,
  periodSummary,
  booksTotal,
  readingDaysTotal,
  notesTotal,
  readingStreak,
  randomHighlight,
  readingDurationTrend,
  completionProgress,
  topBook,
}

/// Default order for dashboard tiles when the user has not customized the layout.
const List<StatisticsDashboardTileType> defaultStatisticsDashboardTiles = [
  StatisticsDashboardTileType.totalTime,
  StatisticsDashboardTileType.libraryTotals,
  StatisticsDashboardTileType.periodSummary,
  StatisticsDashboardTileType.booksTotal,
  StatisticsDashboardTileType.readingDaysTotal,
  StatisticsDashboardTileType.notesTotal,
  StatisticsDashboardTileType.readingStreak,
  StatisticsDashboardTileType.readingDurationTrend,
  StatisticsDashboardTileType.randomHighlight,
  StatisticsDashboardTileType.completionProgress,
  StatisticsDashboardTileType.topBook,
];

const Map<StatisticsDashboardTileType, StatisticsDashboardTileBase>
    dashboardTileRegistry = {
  StatisticsDashboardTileType.totalTime: TotalTimeTile(),
  StatisticsDashboardTileType.libraryTotals: LibraryTotalsTile(),
  StatisticsDashboardTileType.periodSummary: PeriodSummaryTile(),
  StatisticsDashboardTileType.booksTotal: BooksTotalTile(),
  StatisticsDashboardTileType.readingDaysTotal: ReadingDaysTile(),
  StatisticsDashboardTileType.notesTotal: NotesTotalTile(),
  StatisticsDashboardTileType.readingStreak: ReadingStreakTile(),
  StatisticsDashboardTileType.randomHighlight: RandomHighlightTile(),
  StatisticsDashboardTileType.readingDurationTrend: ReadingDurationTrendTile(),
  StatisticsDashboardTileType.completionProgress: CompletionProgressTile(),
  StatisticsDashboardTileType.topBook: TopBookTile(),
};
