import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/providers/reading_completion_provider.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CompletionProgressTile extends StatisticsDashboardTileBase {
  const CompletionProgressTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.completionProgress,
      title: l10n.tileCompletionProgressTitle,
      description: l10n.tileCompletionProgressDescription,
      columnSpan: 4,
      rowSpan: 2,
      icon: Icons.emoji_events_outlined,
    );
  }

  @override
  String get title => metadata.title;

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingCompletionProvider);
    return AsyncSkeletonWrapper<List<Book>>(
      asyncValue: asyncValue,
      mock: [Book.mock()],
      builder: (books, _) => _CompletionContent(books: books),
    );
  }
}

class _CompletionContent extends StatelessWidget {
  const _CompletionContent({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final average = books.isEmpty
        ? 0.0
        : books.fold<double>(0, (acc, book) => acc + book.readingPercentage) /
            books.length;

    return Row(
      children: [
        _CompletionRing(percentage: average),
        const SizedBox(width: 16),
        Expanded(
          child: books.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 28,
                        color: ClaudePalette.tertiary(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.tileCompletionProgressEmptyState,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: ClaudePalette.secondary(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final book = books[index];
                          final percent = (book.readingPercentage * 100)
                              .clamp(0, 100)
                              .toStringAsFixed(0);
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        book.title,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: ClaudePalette.fg(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '$percent%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: ClaudePalette.accent(context),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value:
                                        book.readingPercentage.clamp(0, 1),
                                    minHeight: 4,
                                    color: ClaudePalette.accent(context),
                                    backgroundColor:
                                        ClaudePalette.divider(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tileCompletionProgressMotivation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: ClaudePalette.tertiary(context),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CompletionRing extends StatelessWidget {
  const _CompletionRing({required this.percentage});

  final double percentage;

  @override
  Widget build(BuildContext context) {
    final normalized = percentage.clamp(0, 1);
    return SizedBox(
      width: 108,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: normalized as double,
              strokeWidth: 8,
              color: ClaudePalette.accent(context),
              backgroundColor: ClaudePalette.divider(context),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(normalized * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ClaudePalette.fg(context),
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                L10n.of(context)
                    .tileCompletionProgressAverageLabel
                    .toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: ClaudePalette.secondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
