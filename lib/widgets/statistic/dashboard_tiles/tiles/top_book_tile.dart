import 'package:papertok_reader/models/statistic_data_model.dart';
import 'package:papertok_reader/providers/book_daily_reading_provider.dart';
import 'package:papertok_reader/providers/statistic_data.dart';
import 'package:papertok_reader/utils/date/convert_seconds.dart';
import 'package:papertok_reader/widgets/bookshelf/book_cover.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/book_reading_chart.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/tips/statistic_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBookTile extends StatisticsDashboardTileBase {
  const TopBookTile();

  @override
  get metadata => StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.topBook,
        title: l10nLocal.tileTopBookTitle,
        description: l10nLocal.tileTopBookDescription,
        columnSpan: 4,
        rowSpan: 2,
        icon: Icons.bookmark_added_outlined,
      );

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.favorite);
  }

  @override
  Widget buildContent(
    BuildContext context,
    WidgetRef ref,
  ) {
    return AsyncSkeletonWrapper(
      asyncValue: ref.watch(statisticDataProvider),
      mock: StatisticDataModel.mock(),
      builder: (statisticData, _) {
        if (statisticData.bookReadingTime.isEmpty) {
          return Center(child: FittedBox(child: StatisticsTips()));
        }
        final entry = statisticData.bookReadingTime.first;
        final book = entry.keys.first;
        final seconds = entry.values.first;

        final bookTitleStyle = TextStyle(
          fontSize: 15,
          fontFamily: 'SourceHanSerif',
          fontWeight: FontWeight.w700,
          color: ClaudePalette.fg(context),
          height: 1.25,
          overflow: TextOverflow.ellipsis,
        );
        final bookAuthorStyle = TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: ClaudePalette.secondary(context),
          overflow: TextOverflow.ellipsis,
        );
        final bookReadingTimeStyle = TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ClaudePalette.accent(context),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              book: book,
              width: 80,
              height: 120,
              radius: 6,
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: bookTitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      style: bookAuthorStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      convertSeconds(seconds),
                      style: bookReadingTimeStyle,
                    ),
                    const SizedBox(height: 8),
                    AsyncSkeletonWrapper(
                        asyncValue: ref.watch(
                          bookDailyReadingProvider(bookId: book.id),
                        ),
                        mock: BookDailyReadingData.mock(),
                        builder: (bookReadingData, ready) {
                          return ready
                              ? Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: BookReadingChart(
                                      cumulativeValues:
                                          bookReadingData.readingTimes,
                                      dailySeconds:
                                          bookReadingData.readingTimes,
                                      dates: bookReadingData.dates,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }),
                  ]),
            ),
          ],
        );
      },
    );
  }
}
