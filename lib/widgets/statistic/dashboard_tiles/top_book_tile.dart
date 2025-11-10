import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/tips/statistic_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBookTile extends StatisticsDashboardTileBase {
  const TopBookTile()
      : super(const StatisticsDashboardTileMetadata(
          type: StatisticsDashboardTileType.topBook,
          title: 'Top book', // TODO(l10n)
          description: 'Most read title in the current period.', // TODO(l10n)
          columnSpan: 4,
          rowSpan: 2,
          icon: Icons.bookmark_added_outlined,
        ));

  @override
  Widget buildContent(
    BuildContext context,
    StatisticsDashboardSnapshot _,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Consumer(
      builder: (context, ref, __) {
        final statisticData = ref.watch(statisticDataProvider);
        return statisticData.when(
          data: (data) {
            if (data.bookReadingTime.isEmpty) {
              return FittedBox(child: StatisticsTips());
            }
            final entry = data.bookReadingTime.first;
            final book = entry.keys.first;
            final seconds = entry.values.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metadata.title, style: textTheme.titleMedium),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(convertSeconds(seconds)),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
        );
      },
    );
  }
}
