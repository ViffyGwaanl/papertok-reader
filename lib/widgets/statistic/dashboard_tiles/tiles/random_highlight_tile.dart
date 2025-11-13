import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/providers/random_highlight_provider.dart';
import 'package:anx_reader/utils/date/relative_time_formatter.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RandomHighlightTile extends StatisticsDashboardTileBase {
  const RandomHighlightTile();

  @override
  StatisticsDashboardTileMetadata get metadata =>
      const StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.randomHighlight,
        title: 'Highlight of the day', // TODO(l10n)
        description: 'Shows a random highlight from your notes.', // TODO(l10n)
        columnSpan: 2,
        rowSpan: 2,
        icon: Icons.format_quote,
      );

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.format_quote);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(randomHighlightProvider);
    return AsyncSkeletonWrapper<RandomHighlightData?>(
      asyncValue: asyncValue,
      builder: (data) {
        if (data == null) {
          return _EmptyHighlight(
            onRefresh: () =>
                ref.read(randomHighlightProvider.notifier).refresh(),
          );
        }
        return _HighlightCard(
          data: data,
          onRefresh: () => ref.read(randomHighlightProvider.notifier).refresh(),
        );
      },
      mock: RandomHighlightData(
        note: BookNote(
          bookId: -1,
          content: 'Stay hungry, stay foolish.',
          cfi: '',
          chapter: 'Mock chapter',
          type: 'highlight',
          color: '000000',
          updateTime: DateTime.now(),
        ),
        book: null,
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.data,
    required this.onRefresh,
  });

  final RandomHighlightData data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = data.note.content.trim();
    final timestamp = RelativeTimeFormatter.format(data.note.updateTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“$quote”',
                style: theme.textTheme.titleMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                data.book?.title ?? 'Unknown book', // TODO(l10n)
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
              if (data.note.chapter.isNotEmpty)
                Text(
                  data.note.chapter,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                timestamp,
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Refresh', // TODO(l10n)
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyHighlight extends StatelessWidget {
  const _EmptyHighlight({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sticky_note_2_outlined, size: 32),
        const SizedBox(height: 8),
        Text(
          'No highlights yet.', // TODO(l10n)
          style: theme.textTheme.bodyMedium,
        ),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'), // TODO(l10n)
        ),
      ],
    );
  }
}
