import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/providers/random_highlight_provider.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/date/relative_time_formatter.dart';
import 'package:papertok_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:papertok_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RandomHighlightTile extends StatisticsDashboardTileBase {
  const RandomHighlightTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.randomHighlight,
      title: l10n.tileRandomHighlightTitle,
      description: l10n.tileRandomHighlightDescription,
      columnSpan: 2,
      rowSpan: 2,
      icon: Icons.format_quote,
    );
  }

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.format_quote);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(randomHighlightProvider);
    return AsyncSkeletonWrapper<RandomHighlightData?>(
      asyncValue: asyncValue,
      builder: (data, _) {
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
    final quote = data.note.content.trim();
    final timestamp = RelativeTimeFormatter.format(data.note.updateTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              quote,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: ClaudePalette.fg(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: ClaudePalette.divider(context)),
        const SizedBox(height: 6),
        Text(
          data.book?.title ?? L10n.of(context).randomHighlightUnknownBook,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: ClaudePalette.fg(context),
          ),
        ),
        if (data.note.chapter.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              data.note.chapter,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: ClaudePalette.secondary(context),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                timestamp,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: ClaudePalette.tertiary(context),
                ),
              ),
            ),
            IconButton(
              tooltip: L10n.of(context).commonRefresh,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.sticky_note_2_outlined,
          size: 28,
          color: ClaudePalette.tertiary(context),
        ),
        const SizedBox(height: 8),
        Text(
          L10n.of(context).randomHighlightEmptyState,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: ClaudePalette.secondary(context),
          ),
        ),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(L10n.of(context).commonRefresh),
        ),
      ],
    );
  }
}
