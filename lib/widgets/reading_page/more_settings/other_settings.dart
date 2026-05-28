import 'package:papertok_reader/utils/platform_utils.dart';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/page_turn_mode.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/reading_page.dart';
import 'package:papertok_reader/providers/ai_book_index.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_progress_text.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_service.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/utils/ui/status_bar.dart';
import 'package:papertok_reader/widgets/common/anx_segmented_button.dart';
import 'package:papertok_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:papertok_reader/widgets/reading_page/more_settings/page_turning/page_turn_dropdown.dart';
import 'package:papertok_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:papertok_reader/widgets/reading_page/more_settings/reading_settings.dart'
    show ClaudeSettingsSection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OtherSettings extends ConsumerStatefulWidget {
  const OtherSettings({super.key});

  @override
  ConsumerState<OtherSettings> createState() => _OtherSettingsState();
}

class _OtherSettingsState extends ConsumerState<OtherSettings> {
  AiLibraryIndexJob? _latestJobForBook(
    List<AiLibraryIndexJob> jobs,
    int bookId, {
    bool activeOnly = false,
  }) {
    for (final job in jobs) {
      if (job.bookId != bookId) continue;
      if (activeOnly && !_isActiveIndexJob(job)) continue;
      return job;
    }
    return null;
  }

  bool _isActiveIndexJob(AiLibraryIndexJob job) {
    return job.status == AiLibraryIndexJobStatus.queued ||
        job.status == AiLibraryIndexJobStatus.running ||
        job.status == AiLibraryIndexJobStatus.paused;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AiLibraryIndexQueueState>(
      aiLibraryIndexQueueProvider,
      (previous, next) {
        final bookId = ref.read(currentReadingProvider).book?.id;
        if (bookId == null) return;
        final previousJob = _latestJobForBook(
          previous?.jobs ?? const <AiLibraryIndexJob>[],
          bookId,
        );
        final nextJob = _latestJobForBook(next.jobs, bookId);
        if (previousJob?.status != nextJob?.status ||
            previousJob?.updatedAt != nextJob?.updatedAt) {
          ref.invalidate(currentBookAiIndexInfoProvider);
        }
      },
    );

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
      final queue = ref.watch(aiLibraryIndexQueueProvider);
      final queueNotifier = ref.read(aiLibraryIndexQueueProvider.notifier);
      final infoAsync = ref.watch(currentBookAiIndexInfoProvider);
      final languageCode = Localizations.localeOf(context).languageCode;
      final zh = languageCode == 'zh';

      final book = reading.book;
      final isReading = reading.isReading && book != null;
      final activeJob = book == null
          ? null
          : _latestJobForBook(queue.jobs, book.id, activeOnly: true);
      final latestBookJob =
          book == null ? null : _latestJobForBook(queue.jobs, book.id);

      final canRun = isReading && !idxState.isBusy && activeJob == null;
      final canClear = canRun;

      String indexInfoStatusLabel(String? status) {
        return switch ((status ?? '').trim()) {
          'succeeded' => zh ? '已完成' : 'succeeded',
          'running' => zh ? '索引中' : 'running',
          'failed' => zh ? '失败' : 'failed',
          'idle' => zh ? '空闲' : 'idle',
          _ => zh ? '未知' : 'unknown',
        };
      }

      String jobStatusLabel(AiLibraryIndexJobStatus status) {
        return switch (status) {
          AiLibraryIndexJobStatus.queued => zh ? '等待中' : 'queued',
          AiLibraryIndexJobStatus.running => zh ? '索引中' : 'indexing',
          AiLibraryIndexJobStatus.paused => zh ? '已暂停' : 'paused',
          AiLibraryIndexJobStatus.succeeded => zh ? '已完成' : 'done',
          AiLibraryIndexJobStatus.failed => zh ? '失败' : 'failed',
          AiLibraryIndexJobStatus.cancelled => zh ? '已取消' : 'cancelled',
        };
      }

      String updatedText(int? updatedAt) {
        if (updatedAt == null) return zh ? '暂无' : 'unknown';
        return DateTime.fromMillisecondsSinceEpoch(updatedAt)
            .toLocal()
            .toString();
      }

      String? queueStatusText(AiLibraryIndexJob? job) {
        if (job == null) return null;
        final detail = AiLibraryIndexProgressText.detail(
          job: job,
          languageCode: languageCode,
        );
        final percent = AiLibraryIndexProgressText.formatPercent(job.progress);
        final parts = <String>[
          jobStatusLabel(job.status),
          percent,
          if (detail.isNotEmpty) detail,
        ];
        if (job.lastError != null && job.lastError!.trim().isNotEmpty) {
          parts.add(zh ? '错误：${job.lastError}' : 'error: ${job.lastError}');
        }
        return parts.join(' · ');
      }

      String? legacyStatusText(AiBookIndexingState s) {
        if (s.message == null && !s.isBusy) return null;
        return switch (s.status) {
          AiBookIndexingStatus.idle => null,
          AiBookIndexingStatus.indexing =>
            zh ? '索引中 · ${s.message}' : 'indexing · ${s.message}',
          AiBookIndexingStatus.clearing => zh ? '清除中' : 'clearing',
          AiBookIndexingStatus.done => zh ? '索引已更新' : 'index updated',
          AiBookIndexingStatus.error =>
            zh ? '错误 · ${s.message}' : 'error · ${s.message}',
        };
      }

      return Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? 'AI 语义索引（当前书籍）' : 'AI Semantic Index (Current Book)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ClaudePalette.fg(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (!isReading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  zh
                      ? '打开一本书后，可以为当前书籍建立语义索引。'
                      : 'Open a book to build a semantic index.',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
              ),
            if (isReading)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  zh ? '书籍：${book.title}' : 'Book: ${book.title}',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: infoAsync.when(
                data: (info) {
                  final chunks = info?.chunkCount ?? 0;
                  final status = indexInfoStatusLabel(info?.indexStatus);
                  return Text(
                    zh
                        ? '已索引 chunks：$chunks · 状态：$status · 更新：${updatedText(info?.updatedAt)}'
                        : 'Indexed chunks: $chunks · status: $status · updated: ${updatedText(info?.updatedAt)}',
                    style: Theme.of(
                      context,
                    )
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: ClaudePalette.tertiary(context)),
                  );
                },
                loading: () => Text(
                  zh ? '正在读取索引状态…' : 'Loading index status…',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
                error: (e, _) => Text(
                  zh ? '索引状态不可用：$e' : 'Index status unavailable: $e',
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
              ),
            ),
            if (queueStatusText(activeJob ?? latestBookJob) != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  queueStatusText(activeJob ?? latestBookJob)!,
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
              ),
            if (legacyStatusText(idxState) != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  legacyStatusText(idxState)!,
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: ClaudePalette.tertiary(context)),
                ),
              ),
            if (activeJob != null || idxState.isBusy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: activeJob?.progress.clamp(0.0, 1.0) ??
                      idxState.progress.clamp(0.0, 1.0),
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
                            AnxToast.show(
                              zh ? '已加入 AI 索引队列' : 'Added to AI index queue.',
                            );
                            await queueNotifier.enqueueBook(
                              book.id,
                              forceRebuild: false,
                            );
                            ref.invalidate(currentBookAiIndexInfoProvider);
                          }
                        : null,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(zh ? '构建' : 'Build'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canRun
                        ? () async {
                            AnxToast.show(
                              zh ? '已加入重建队列' : 'Added rebuild job.',
                            );
                            await queueNotifier.enqueueBook(
                              book.id,
                              forceRebuild: true,
                            );
                            ref.invalidate(currentBookAiIndexInfoProvider);
                          }
                        : null,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(zh ? '重建' : 'Rebuild'),
                  ),
                  TextButton.icon(
                    onPressed: canClear
                        ? () async {
                            AnxToast.show(
                              zh ? '正在清除语义索引…' : 'Clearing semantic index…',
                            );
                            await notifier.clearIndex();
                            await queueNotifier.refresh();
                            ref.invalidate(currentBookAiIndexInfoProvider);
                          }
                        : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(zh ? '清除' : 'Clear'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClaudeSettingsSection(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              fullScreen(),
              if (AnxPlatform.isAndroid) keyboardTurnPage(),
              swapPageTurnArea(),
              showMenuOnHover(),
            ],
          ),
          ClaudeSettingsSection(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              autoAdjustReadingTheme(),
              autoTranslateSelection(),
              autoMarkSelection(),
              autoSummaryPreviousContent(),
            ],
          ),
          ClaudeSettingsSection(
            children: [aiIndexSection()],
          ),
          ClaudeSettingsSection(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [screenTimeout()],
          ),
          ClaudeSettingsSection(
            children: [pageTurningControl()],
          ),
        ],
      ),
    );
  }
}
