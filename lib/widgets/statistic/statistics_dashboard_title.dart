import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';

// Provider to track current page index in IntroductionScreen
final _currentPageIndexProvider = StateProvider<int>((ref) => 0);

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
    final l10n = L10n.of(context);

    void showAddTileSheet() {
      if (availableTiles.isEmpty) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return AddTileSheetContent();
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: TotalReadTime()),
          if (tilesState.isEditing)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: availableTiles.isEmpty ? null : showAddTileSheet,
                  icon: const Icon(Icons.add),
                  tooltip: l10n.statisticsDashboardAddCard,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: notifier.saveLayout,
                  icon: const Icon(Icons.save),
                  tooltip: l10n.commonSave,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AddTileSheetContent extends ConsumerStatefulWidget {
  const AddTileSheetContent({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddTileSheetContentState();
}

class _AddTileSheetContentState extends ConsumerState<AddTileSheetContent> {
  late final List<StatisticsDashboardTileType> availableTiles;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(dashboardTilesProvider.notifier);
    availableTiles = notifier.availableTiles;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(dashboardTilesProvider.notifier);

    final currentIndex = ref.watch(_currentPageIndexProvider);

    // Bounds checking to prevent IndexError
    if (availableTiles.isEmpty) {
      return const SizedBox.shrink();
    }

    // Ensure currentIndex is within valid bounds
    final validIndex = currentIndex.clamp(0, availableTiles.length - 1);
    if (currentIndex != validIndex) {
      // Schedule index correction for next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(_currentPageIndexProvider.notifier).state = validIndex;
        }
      });
    }
    final l10n = L10n.of(context);

    return FilledContainer(
      color: Theme.of(context).scaffoldBackgroundColor,
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  l10n.statisticsDashboardAddTileTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // Introduction Screen
          Expanded(
            child: IntroductionScreen(
              showDoneButton: false,
              pages: availableTiles.map((type) {
                final dashboardTile = dashboardTileRegistry[type]!;
                final metadata = dashboardTile.metadata;
                return PageViewModel(
                    titleWidget: Text(
                      metadata.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    bodyWidget: Column(
                      children: [
                        SizedBox(
                            height: dashboardTile.tileSize(context).height,
                            width: dashboardTile.tileSize(context).width,
                            child: dashboardTile.buildTile(context, ref)),
                        SizedBox(height: 40),
                        Text(
                          metadata.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    decoration: PageDecoration(
                      bodyPadding: EdgeInsets.all(0),
                      pageMargin: EdgeInsets.all(0),
                    ));
              }).toList(),
              onDone: () {
                // Navigator.pop(context);
              },
              onChange: (index) {
                ref.read(_currentPageIndexProvider.notifier).state = index;
              },
              showBackButton: false,
              showNextButton: false,
              dotsDecorator: DotsDecorator(
                size: const Size.square(10.0),
                activeSize: const Size(20.0, 10.0),
                activeColor: Theme.of(context).primaryColor,
                color: ClaudePalette.divider(context),
                spacing: const EdgeInsets.symmetric(horizontal: 3.0),
                activeShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25.0),
                ),
              ),
            ),
          ),
          // Add Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: AnxButton.icon(
                disabled:
                    notifier.workingTiles.contains(availableTiles[validIndex]),
                onPressed: () {
                  notifier.addTile(availableTiles[validIndex]);
                  setState(() {});
                },
                icon: const Icon(Icons.add),
                label: Text(
                  l10n.statisticsDashboardAddTileButton(
                    dashboardTileRegistry[availableTiles[validIndex]]!
                        .metadata
                        .title,
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TotalReadTime extends ConsumerWidget {
  const TotalReadTime({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncSkeletonWrapper<int>(
        asyncValue: ref.watch(totalReadingTimeProvider),
        builder: (seconds, _) {
          final hours = seconds ~/ 3600;
          final minutes = (seconds % 3600) ~/ 60;

          final numberStyle = TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: ClaudePalette.fg(context),
            letterSpacing: -0.5,
            height: 1.05,
          );
          final unitStyle = TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: ClaudePalette.secondary(context),
            letterSpacing: -0.2,
            height: 1.05,
          );

          String hourLabel = L10n.of(context).commonHours(hours);
          String minuteLabel = L10n.of(context).commonMinutes(minutes);
          // Split into number + unit so unit sits on the baseline at 18/w500.
          final hourSuffix = hourLabel.replaceAll(RegExp(r'[0-9]'), '').trim();
          final minuteSuffix =
              minuteLabel.replaceAll(RegExp(r'[0-9]'), '').trim();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: hours.toString(), style: numberStyle),
                  if (hourSuffix.isNotEmpty)
                    TextSpan(text: hourSuffix, style: unitStyle),
                  const TextSpan(text: ' '),
                  TextSpan(text: minutes.toString(), style: numberStyle),
                  if (minuteSuffix.isNotEmpty)
                    TextSpan(text: minuteSuffix, style: unitStyle),
                ]),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${Prefs().beginDate.toString().substring(0, 10)} ${L10n.of(context).statisticToPresent}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: ClaudePalette.secondary(context),
                ),
              )
            ],
          );
        });
  }
}
