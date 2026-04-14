import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/providers/last_read_book_provider.dart';
import 'package:papertok_reader/service/book.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/date/relative_time_formatter.dart';
import 'package:papertok_reader/widgets/bookshelf/book_cover.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContinueReadingTile extends StatisticsDashboardTileBase {
  const ContinueReadingTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.continueReading,
      title: l10n.tileContinueReadingTitle,
      description: l10n.tileContinueReadingDescription,
      columnSpan: 2,
      rowSpan: 1,
      icon: Icons.play_arrow_rounded,
    );
  }

  @override
  bool get canFlip => false;

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.play_circle_outline);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(lastReadBookProvider);

    return AsyncSkeletonWrapper<LastReadBookData?>(
      asyncValue: asyncValue,
      mock: LastReadBookData(
        book: Book.mock(),
        lastReadDate: DateTime.now(),
      ),
      builder: (data, _) {
        if (data == null) {
          return _EmptyState(
            onRefresh: () => ref.read(lastReadBookProvider.notifier).refresh(),
          );
        }
        final book = data.book;
        final heroTag = 'continue_reading_${book.id}';
        return _ContinueReadingContent(
          book: book,
          lastReadDate: data.lastReadDate,
          heroTag: heroTag,
        );
      },
    );
  }

  @override
  void onTap(BuildContext context, WidgetRef ref) {
    final data = ref.read(lastReadBookProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final book = data?.book;
    if (book == null) return;
    final heroTag = 'continue_reading_${book.id}';
    // Don't pass cfi parameter, let the book open from its saved position
    // This allows reading progress to be saved (same behavior as bookshelf)
    pushToReadingPage(ref, context, book, heroTag: heroTag);
  }
}

class _ContinueReadingContent extends StatelessWidget {
  const _ContinueReadingContent({
    required this.book,
    required this.lastReadDate,
    required this.heroTag,
  });

  final Book book;
  final DateTime? lastReadDate;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final subtitle = lastReadDate == null
        ? L10n.of(context).tileContinueReadingNoTimestamp
        : RelativeTimeFormatter.format(lastReadDate!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Hero(
          tag: heroTag,
          child: BookCover(
            book: book,
            width: 56,
            height: 80,
            radius: 6,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ClaudePalette.fg(context),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: ClaudePalette.secondary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: ClaudePalette.tertiary(context),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: book.readingPercentage.clamp(0, 1),
                  minHeight: 4,
                  color: ClaudePalette.accent(context),
                  backgroundColor: ClaudePalette.divider(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 28,
          color: ClaudePalette.tertiary(context),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tileContinueReadingEmptyState,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: ClaudePalette.secondary(context),
          ),
          textAlign: TextAlign.center,
        ),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(l10n.commonRefresh),
        ),
      ],
    );
  }
}
