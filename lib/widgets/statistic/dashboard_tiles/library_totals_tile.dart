import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:flutter/material.dart';

class LibraryTotalsTile extends StatelessWidget {
  const LibraryTotalsTile({
    super.key,
    required this.snapshot,
    required this.metadata,
  });

  final StatisticsDashboardSnapshot snapshot;
  final StatisticsDashboardTileMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metadata.title, style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NumberTile(
                icon: Icons.auto_stories,
                label: l10n.statisticBooksRead(snapshot.totalBooks),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberTile(
                icon: Icons.calendar_today,
                label: l10n.statisticDaysOfReading(snapshot.totalDays),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberTile(
                icon: Icons.note_alt_outlined,
                label: l10n.statisticNotes(snapshot.totalNotes),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
