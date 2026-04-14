import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryTotalsTile extends StatisticsDashboardTileBase {
  const LibraryTotalsTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.libraryTotals,
      title: l10n.tileLibraryTotalsTitle,
      description: l10n.tileLibraryTotalsDescription,
      columnSpan: 4,
      rowSpan: 1,
      icon: Icons.menu_book_outlined,
    );
  }

  @override
  Widget buildContent(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = L10n.of(context);

    return AsyncSkeletonWrapper<List>(
        asyncValue: combineAsyncValues([
          ref.watch(StaticticsSummaryValueProvider(StatisticType.totalBooks)),
          ref.watch(StaticticsSummaryValueProvider(StatisticType.totalDates)),
          ref.watch(StaticticsSummaryValueProvider(StatisticType.totalNotes)),
        ]),
        mock: [0, 0, 0],
        builder: (data, _) {
          final booksRead = data[0] as int;
          final daysOfReading = data[1] as int;
          final notesCount = data[2] as int;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _NumberTile(
                  icon: Icons.auto_stories_outlined,
                  value: booksRead,
                  rawLabel: l10n.statisticBooksRead(booksRead),
                ),
              ),
              _VerticalDivider(),
              Expanded(
                child: _NumberTile(
                  icon: Icons.calendar_today_outlined,
                  value: daysOfReading,
                  rawLabel: l10n.statisticDaysOfReading(daysOfReading),
                ),
              ),
              _VerticalDivider(),
              Expanded(
                child: _NumberTile(
                  icon: Icons.note_alt_outlined,
                  value: notesCount,
                  rawLabel: l10n.statisticNotes(notesCount),
                ),
              ),
            ],
          );
        });
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: ClaudePalette.divider(context),
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.icon,
    required this.value,
    required this.rawLabel,
  });

  final IconData icon;
  final int value;
  final String rawLabel;

  @override
  Widget build(BuildContext context) {
    // Strip numbers to isolate the unit part of the localized label.
    final unit = rawLabel.replaceAll(RegExp(r'[0-9\s]'), '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ClaudePalette.secondary(context)),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ClaudePalette.fg(context),
              letterSpacing: -0.3,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
