import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/reading_completion_provider.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CompletionProgressTile extends StatisticsDashboardTileBase {
  const CompletionProgressTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.completionProgress,
        title: 'Almost finished', // TODO(l10n)
        description:
            'Books that are close to completion with a progress ring.', // TODO(l10n)
        columnSpan: 4,
        rowSpan: 2,
        icon: Icons.emoji_events_outlined,
      );

  @override
  String get title => metadata.title;

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingCompletionProvider);
    return AsyncSkeletonWrapper<List<Book>>(
      asyncValue: asyncValue,
      mock: [
        Book(
          id: 1,
          title: 'Mock Book',
          coverPath: '',
          filePath: '',
          lastReadPosition: '',
          readingPercentage: 0.78,
          author: 'Anx',
          isDeleted: false,
          rating: 0,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ],
      builder: (books) => _CompletionContent(books: books),
    );
  }
}

class _CompletionContent extends StatelessWidget {
  const _CompletionContent({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = books.isEmpty
        ? 0.0
        : books.fold<double>(0, (acc, book) => acc + book.readingPercentage) /
            books.length;

    return Row(
      children: [
        _CompletionRing(percentage: average),
        const SizedBox(width: 12),
        Expanded(
          child: books.isEmpty
              ? Center(
                  child: Text(
                    'No books near the finish line.', // TODO(l10n)
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final book = books[index];
                          final percent = (book.readingPercentage * 100)
                              .clamp(0, 100)
                              .toStringAsFixed(0);
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  book.title,
                                  style: theme.textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$percent%',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          );
                        },
                        separatorBuilder: (_, __) =>
                            const Divider(height: 12, thickness: 0.4),
                      ),
                    ),
                    Text(
                      'Keep pushing through the final chapters!', // TODO(l10n)
                      style: theme.textTheme.bodySmall,
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
    final theme = Theme.of(context);
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: normalized as double,
            strokeWidth: 10,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(normalized * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.headlineSmall,
              ),
              Text(
                'avg progress', // TODO(l10n)
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
