import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticsDashboardTitle extends ConsumerStatefulWidget {
  const StatisticsDashboardTitle({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _StatisticDashboardTitleState();
}

class _StatisticDashboardTitleState
    extends ConsumerState<StatisticsDashboardTitle> {
  @override
  Widget build(BuildContext context) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final availableTiles = notifier.availableTiles;

    void showAddTileSheet() {
      if (availableTiles.isEmpty) return;
      showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableTiles.length,
              itemBuilder: (context, index) {
                final type = availableTiles[index];
                final metadata = dashboardTileRegistry[type]!.metadata;
                return ListTile(
                  leading: Icon(metadata.icon),
                  title: Text(metadata.title),
                  subtitle: Text(metadata.description),
                  onTap: () {
                    Navigator.pop(context);
                    notifier.addTile(type);
                  },
                );
              },
            ),
          );
        },
      );
    }

    return Row(
      children: [
        TotalReadTime(),
        const Spacer(),
        if (tilesState.isEditing)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: availableTiles.isEmpty ? null : showAddTileSheet,
                icon: const Icon(Icons.add),
                tooltip: 'Add card', // TODO(l10n)
              ),
              // IconButton(
              //   onPressed: notifier.discardChanges,
              //   icon: const Icon(Icons.close),
              //   tooltip: 'Discard',
              // ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: notifier.saveLayout,
                icon: const Icon(Icons.save),
                tooltip: 'Save layout', // TODO(l10n)
              ),
            ],
          ),
      ],
    );
  }
}

class TotalReadTime extends ConsumerWidget {
  const TotalReadTime({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalReadingTime = ref.watch(totalReadingTimeProvider);

    TextStyle textStyle = const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.bold,
    );

    TextStyle digitStyle = const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );

    return totalReadingTime.when(
      data: (totalSeconds) {
        // 12 h 34 m
        int H = totalSeconds ~/ 3600;
        int M = (totalSeconds % 3600) ~/ 60;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                highlightDigit(
                  context,
                  L10n.of(context).commonHours(H),
                  digitStyle,
                  textStyle,
                ),
                highlightDigit(
                  context,
                  L10n.of(context).commonMinutes(M),
                  digitStyle,
                  textStyle,
                ),
              ],
            ),
            Text(
              '${Prefs().beginDate.toString().substring(0, 10)} ${L10n.of(context).statisticToPresent}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            )
          ],
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }
}
