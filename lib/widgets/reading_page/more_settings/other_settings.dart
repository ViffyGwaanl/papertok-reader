import 'package:anx_reader/utils/platform_utils.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/page_turn_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/ai_book_index.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ui/status_bar.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/page_turn_dropdown.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OtherSettings extends ConsumerStatefulWidget {
  const OtherSettings({super.key});

  @override
  ConsumerState<OtherSettings> createState() => _OtherSettingsState();
}

class _OtherSettingsState extends ConsumerState<OtherSettings> {
  @override
  Widget build(BuildContext context) {
    Widget screenTimeout() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          L10n.of(context).readingPageScreenTimeout,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leadingAndTrailingTextStyle: TextStyle(
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge!.color,
        ),
        subtitle: Row(
          children: [
            Text(L10n.of(context).commonMinutes(Prefs().awakeTime)),
            Expanded(
              child: Slider(
                min: 0,
                max: 60,
                label: Prefs().awakeTime.toString(),
                value: Prefs().awakeTime.toDouble(),
                onChangeEnd: (value) => setState(() {
                  readingPageKey.currentState?.setAwakeTimer(value.toInt());
                }),
                onChanged: (value) => setState(() {
                  Prefs().awakeTime = value.toInt();
                }),
              ),
            ),
          ],
        ),
      );
    }

    ListTile fullScreen() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
          value: Prefs().hideStatusBar,
          onChanged: (bool? value) => setState(() {
            Prefs().saveHideStatusBar(value!);
            if (value) {
              hideStatusBar();
            } else {
              showStatusBar();
            }
          }),
        ),
        title: Text(L10n.of(context).readingPageFullScreen),
      );
    }

    Widget pageTurningControl() {
      int currentType = Prefs().pageTurningType;
      ScrollController scrollController = ScrollController();
      PageTurnMode currentMode = PageTurnMode.fromCode(Prefs().pageTurnMode);

      return StatefulBuilder(
        builder:
            (BuildContext context, void Function(void Function()) setState) {
              void onTap(int index) {
                setState(() {
                  Prefs().pageTurningType = index;
                  currentType = index;
                });
              }

              void onModeChanged(Set<PageTurnMode> selected) {
                setState(() {
                  currentMode = selected.first;
                  Prefs().pageTurnMode = selected.first.code;
                });
              }

              void onCustomConfigChanged(int index, PageTurningType type) {
                List<int> config = Prefs().customPageTurnConfig;
                config[index] = type.index;
                Prefs().customPageTurnConfig = config;
              }

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.of(context).readingPagePageTurningMethod,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    AnxSegmentedButton<PageTurnMode>(
                      segments: [
                        SegmentButtonItem(
                          value: PageTurnMode.simple,
                          label: L10n.of(context).pageTurnModeSimple,
                        ),
                        SegmentButtonItem(
                          value: PageTurnMode.custom,
                          label: L10n.of(context).pageTurnModeCustom,
                        ),
                      ],
                      selected: {currentMode},
                      onSelectionChanged: onModeChanged,
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    if (currentMode == PageTurnMode.simple) ...[
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: pageTurningTypes.length,
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: getPageTurningDiagram(
                                context,
                                pageTurningTypes[index],
                                pageTurningIcons[index],
                                currentType == index,
                                () {
                                  onTap(index);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ] else ...[
                      Text(
                        L10n.of(context).customPageTurnConfig,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          for (int row = 0; row < 3; row++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  for (int col = 0; col < 3; col++)
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: col < 2 ? 8.0 : 0,
                                        ),
                                        child: Builder(
                                          builder: (context) {
                                            int index = row * 3 + col;
                                            List<int> config =
                                                Prefs().customPageTurnConfig;
                                            return PageTurnDropdown(
                                              value: PageTurningType
                                                  .values[config[index]],
                                              onChanged: (type) {
                                                if (type != null) {
                                                  setState(() {
                                                    onCustomConfigChanged(
                                                      index,
                                                      type,
                                                    );
                                                  });
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
      );
    }

    Widget autoTranslateSelection() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
          value: Prefs().autoTranslateSelection,
          onChanged: (bool value) => setState(() {
            Prefs().autoTranslateSelection = value;
          }),
        ),
        title: Text(L10n.of(context).readingPageAutoTranslateSelection),
      );
    }

    ListTile autoSummaryPreviousContent() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageAutoSummaryPreviousContent),
        trailing: Switch(
          value: Prefs().autoSummaryPreviousContent,
          onChanged: (bool value) => setState(() {
            Prefs().autoSummaryPreviousContent = value;
          }),
        ),
      );
    }

    Widget autoMarkSelection() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
          value: Prefs().autoMarkSelection,
          onChanged: (bool value) => setState(() {
            Prefs().autoMarkSelection = value;
          }),
        ),
        title: Text(L10n.of(context).readingPageAutoMarkSelection),
        subtitle: Text(L10n.of(context).readingPageAutoMarkSelectionTips),
      );
    }

    ListTile autoAdjustReadingTheme() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageAutoAdjustReadingTheme),
        subtitle: Text(L10n.of(context).readingPageAutoAdjustReadingThemeTips),
        trailing: Switch(
          value: Prefs().autoAdjustReadingTheme,
          onChanged: (bool value) => setState(() {
            Prefs().autoAdjustReadingTheme = value;
          }),
        ),
      );
    }

    ListTile keyboardTurnPage() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageVolumeKeyTurnPage),
        trailing: Switch(
          value: Prefs().volumeKeyTurnPage,
          onChanged: (bool value) => setState(() {
            Prefs().volumeKeyTurnPage = value;
          }),
        ),
      );
    }

    ListTile swapPageTurnArea() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageSwapPageTurnArea),
        subtitle: Text(L10n.of(context).readingPageSwapPageTurnAreaTips),
        trailing: Switch(
          value: Prefs().swapPageTurnArea,
          onChanged: (bool value) => setState(() {
            Prefs().swapPageTurnArea = value;
          }),
        ),
      );
    }

    ListTile showMenuOnHover() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageShowMenuOnHover),
        subtitle: Text(L10n.of(context).readingPageShowMenuOnHoverTips),
        trailing: Switch(
          value: Prefs().showMenuOnHover,
          onChanged: (bool value) => setState(() {
            Prefs().showMenuOnHover = value;
          }),
        ),
      );
    }

    Widget aiIndexSection() {
      final reading = ref.watch(currentReadingProvider);
      final idxState = ref.watch(aiBookIndexingProvider);
      final notifier = ref.read(aiBookIndexingProvider.notifier);
      final infoAsync = ref.watch(currentBookAiIndexInfoProvider);

      final book = reading.book;
      final isReading = reading.isReading && book != null;

      final canRun = isReading && !idxState.isBusy;

      String statusText(AiBookIndexingState s) {
        switch (s.status) {
          case AiBookIndexingStatus.idle:
            return 'Idle';
          case AiBookIndexingStatus.indexing:
            return 'Indexing…';
          case AiBookIndexingStatus.clearing:
            return 'Clearing…';
          case AiBookIndexingStatus.done:
            return 'Done';
          case AiBookIndexingStatus.error:
            return 'Error';
        }
      }

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Text(
              'AI Semantic Index (Current Book)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!isReading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Open a book to build a semantic index.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            if (isReading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Book: ${book!.title}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: infoAsync.when(
                data: (info) {
                  final chunks = info?.chunkCount ?? 0;
                  final updatedAt = info?.updatedAt;
                  final updatedText = updatedAt == null
                      ? 'unknown'
                      : DateTime.fromMillisecondsSinceEpoch(
                          updatedAt,
                        ).toLocal().toString();
                  return Text(
                    'Indexed chunks: $chunks (updated: $updatedText)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  );
                },
                loading: () => Text(
                  'Loading index status…',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                error: (e, _) => Text(
                  'Index status unavailable: $e',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            ),
            if (idxState.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${statusText(idxState)} · ${idxState.message}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            if (idxState.isBusy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: idxState.progress.clamp(0.0, 1.0),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: canRun
                        ? () async {
                            AnxToast.show('Building semantic index…');
                            await notifier.buildIndex(rebuild: false);
                          }
                        : null,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Build'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canRun
                        ? () async {
                            AnxToast.show('Rebuilding semantic index…');
                            await notifier.buildIndex(rebuild: true);
                          }
                        : null,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Rebuild'),
                  ),
                  TextButton.icon(
                    onPressed: canRun
                        ? () async {
                            AnxToast.show('Clearing semantic index…');
                            await notifier.clearIndex();
                          }
                        : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          fullScreen(),
          if (AnxPlatform.isAndroid) keyboardTurnPage(),
          swapPageTurnArea(),
          showMenuOnHover(),
          autoAdjustReadingTheme(),
          autoTranslateSelection(),
          autoMarkSelection(),
          autoSummaryPreviousContent(),
          aiIndexSection(),
          screenTimeout(),
          pageTurningControl(),
        ],
      ),
    );
  }
}
