import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/service/rag/ai_book_indexer.dart';
import 'package:anx_reader/service/rag/ai_embeddings_service.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/ai_text_chunker.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Filter {
  unindexed,
  expired,
  indexed,
}

enum _BookIndexStatus {
  unindexed,
  expired,
  indexed,
}

class _BookRow {
  const _BookRow({
    required this.result,
    required this.status,
    required this.indexInfo,
  });

  final BookSearchResult result;
  final _BookIndexStatus status;
  final AiBookIndexInfo? indexInfo;

  int get bookId => result.book.id;
}

class AiLibraryIndexPage extends ConsumerStatefulWidget {
  const AiLibraryIndexPage({super.key});

  @override
  ConsumerState<AiLibraryIndexPage> createState() => _AiLibraryIndexPageState();
}

class _AiLibraryIndexPageState extends ConsumerState<AiLibraryIndexPage> {
  static const int _bookListLimit = 200;

  _Filter _filter = _Filter.unindexed;
  bool _selecting = false;
  final Set<int> _selectedBookIds = {};

  Future<List<_BookRow>>? _booksFuture;

  Timer? _refreshDebounce;
  int _loadToken = 0;
  List<int> _currentVisibleBookIds = const [];

  @override
  void initState() {
    super.initState();

    _booksFuture = _loadBooks(filter: _filter, token: ++_loadToken);

    // The queue updates fairly frequently (progress), so debounce book list
    // refreshes to avoid jitter.
    ref.listen<AiLibraryIndexQueueState>(aiLibraryIndexQueueProvider,
        (prev, next) {
      _scheduleBooksRefresh(const Duration(milliseconds: 900));
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _scheduleBooksRefresh(Duration debounce) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(debounce, () {
      if (!mounted) return;
      setState(() {
        _booksFuture = _loadBooks(filter: _filter, token: ++_loadToken);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final queue = ref.watch(aiLibraryIndexQueueProvider);
    final queueSvc = ref.read(aiLibraryIndexQueueProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiLibraryIndexTitle),
        actions: _selecting
            ? [
                TextButton(
                  onPressed:
                      _currentVisibleBookIds.isEmpty ? null : _handleSelectAll,
                  child: Text(l10n.aiLibraryIndexActionSelectAll),
                ),
                TextButton(
                  onPressed:
                      _selectedBookIds.isEmpty ? null : _handleClearSelection,
                  child: Text(l10n.aiLibraryIndexActionClearSelection),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () {
                    setState(() {
                      _selecting = false;
                      _selectedBookIds.clear();
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selecting = true;
                      _selectedBookIds.clear();
                    });
                  },
                  child: Text(l10n.aiLibraryIndexActionSelect),
                ),
              ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                l10n.settingsAiLibraryIndexSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _buildConfigTile(context),
            _buildFilterBar(context),
            const Divider(height: 1),
            _buildQueueSection(context, queue, queueSvc),
            const Divider(height: 1),
            _buildBooksSection(context),
          ],
        ),
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _selectedBookIds.isEmpty
                            ? null
                            : _handleClearSelection,
                        child: Text(l10n.aiLibraryIndexActionClearSelection),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selectedBookIds.isEmpty
                            ? null
                            : () async {
                                final ids = _selectedBookIds.toList();
                                await queueSvc.enqueueBooks(ids);
                                if (!mounted) return;
                                setState(() {
                                  _selecting = false;
                                  _selectedBookIds.clear();
                                });
                                _scheduleBooksRefresh(
                                  const Duration(milliseconds: 500),
                                );
                              },
                        child: Text(l10n.aiLibraryIndexActionEnqueue),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  void _handleSelectAll() {
    setState(() {
      _selectedBookIds.addAll(_currentVisibleBookIds);
    });
  }

  void _handleClearSelection() {
    setState(() {
      _selectedBookIds.clear();
    });
  }

  Widget _buildConfigTile(BuildContext context) {
    final l10n = L10n.of(context);

    final follow = Prefs().aiLibraryIndexFollowSelectedProvider;
    final providerId = Prefs().aiLibraryIndexProviderIdEffective;
    final providerName =
        Prefs().getAiProviderMeta(providerId)?.name ?? providerId;
    final embeddingModel = Prefs().aiLibraryIndexEmbeddingModelEffective;

    final chunkTargetChars = Prefs().aiLibraryIndexChunkTargetChars;
    final chunkMaxChars = Prefs().aiLibraryIndexChunkMaxChars;
    final chunkMinChars = Prefs().aiLibraryIndexChunkMinChars;
    final chunkOverlapChars = Prefs().aiLibraryIndexChunkOverlapChars;
    final maxChapterChars = Prefs().aiLibraryIndexMaxChapterCharacters;

    final line1 = follow
        ? l10n.aiLibraryIndexConfigSummaryFollow(providerName, embeddingModel)
        : l10n.aiLibraryIndexConfigSummaryExplicit(
            providerName, embeddingModel);

    final line2 = l10n.aiLibraryIndexConfigSummaryChunk(
      chunkTargetChars,
      chunkMaxChars,
      chunkMinChars,
      chunkOverlapChars,
      maxChapterChars,
    );

    return ListTile(
      leading: const Icon(Icons.tune),
      title: Text(l10n.aiLibraryIndexConfigTitle),
      subtitle: Text('$line1\n$line2'),
      isThreeLine: true,
      onTap: () => _showIndexConfigDialog(context),
    );
  }

  Future<void> _showIndexConfigDialog(BuildContext context) async {
    final l10n = L10n.of(context);

    var follow = Prefs().aiLibraryIndexFollowSelectedProvider;
    var providerId = Prefs().aiLibraryIndexProviderId;

    final modelController = TextEditingController(
      text: Prefs().aiLibraryIndexEmbeddingModel.trim(),
    );

    final targetController = TextEditingController(
      text: Prefs().aiLibraryIndexChunkTargetChars.toString(),
    );
    final maxController = TextEditingController(
      text: Prefs().aiLibraryIndexChunkMaxChars.toString(),
    );
    final minController = TextEditingController(
      text: Prefs().aiLibraryIndexChunkMinChars.toString(),
    );
    final overlapController = TextEditingController(
      text: Prefs().aiLibraryIndexChunkOverlapChars.toString(),
    );
    final maxChapterController = TextEditingController(
      text: Prefs().aiLibraryIndexMaxChapterCharacters.toString(),
    );

    final batchSizeController = TextEditingController(
      text: Prefs().aiLibraryIndexEmbeddingBatchSize.toString(),
    );
    final timeoutController = TextEditingController(
      text: Prefs().aiLibraryIndexEmbeddingsTimeoutSeconds.toString(),
    );

    List<String> eligibleProviderIds() {
      final providers = Prefs().aiProvidersV1;
      return providers
          .where(
            (p) =>
                p.enabled &&
                (p.type == AiProviderType.openaiCompatible ||
                    p.type == AiProviderType.openaiResponses),
          )
          .map((p) => p.id)
          .toList(growable: false);
    }

    int parseIntOr(String raw, int fallback) {
      final v = int.tryParse(raw.trim());
      return v ?? fallback;
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              final eligible = eligibleProviderIds();

              // Keep providerId valid.
              if (!eligible.contains(providerId)) {
                providerId = eligible.isEmpty ? '' : eligible.first;
              }

              Future<void> pickEmbeddingModel() async {
                final providerIdForModels = (follow
                        ? Prefs().aiLibraryIndexProviderIdEffective
                        : providerId)
                    .trim();

                final meta = Prefs().getAiProviderMeta(providerIdForModels);
                if (meta == null) {
                  AnxToast.show(l10n.aiServiceNotConfigured);
                  return;
                }

                var models =
                    Prefs().getAiModelsCacheV1(providerIdForModels)?.models ??
                        const <String>[];
                var loading = false;

                List<String> filterEmbeddingModels(List<String> raw) {
                  final embed = raw.where((e) {
                    final s = e.toLowerCase();
                    return s.contains('embed') || s.contains('embedding');
                  }).toList(growable: false);
                  return embed.isNotEmpty ? embed : raw;
                }

                await showModalBottomSheet<void>(
                  context: ctx,
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, setModalState) {
                        Future<void> refresh() async {
                          if (loading) return;
                          setModalState(() {
                            loading = true;
                          });

                          try {
                            final rawConfig =
                                Prefs().getAiConfig(providerIdForModels);
                            if (rawConfig.isEmpty) {
                              AnxToast.show(l10n.aiServiceNotConfigured);
                              return;
                            }

                            final fetched = await AiModelsService.fetchModels(
                              provider: meta,
                              rawConfig: rawConfig,
                            );

                            if (fetched.isNotEmpty) {
                              Prefs().saveAiModelsCacheV1(
                                  providerIdForModels, fetched);
                            }

                            models = fetched;
                          } catch (_) {
                            AnxToast.show(l10n.commonFailed);
                          } finally {
                            setModalState(() {
                              loading = false;
                            });
                          }
                        }

                        final visibleModels = filterEmbeddingModels(models);

                        return SafeArea(
                          child: ListView(
                            children: [
                              ListTile(
                                title: Text(
                                    l10n.aiLibraryIndexConfigModelDefaultTitle),
                                subtitle: Text(
                                    l10n.aiLibraryIndexConfigModelDefaultDesc(
                                  AiEmbeddingsService.defaultEmbeddingModel,
                                )),
                                trailing: modelController.text.trim().isEmpty
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () {
                                  modelController.text = '';
                                  Navigator.pop(context);
                                  setState(() {});
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: Text(
                                    l10n.aiLibraryIndexConfigModelCustomTitle),
                                subtitle: Text(
                                    l10n.aiLibraryIndexConfigModelCustomDesc),
                                onTap: () async {
                                  final controller = TextEditingController(
                                    text: modelController.text.trim(),
                                  );

                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (context) {
                                      return AlertDialog(
                                        title: Text(l10n
                                            .aiLibraryIndexConfigModelCustomTitle),
                                        content: TextField(
                                          controller: controller,
                                          decoration: InputDecoration(
                                            hintText: l10n
                                                .aiLibraryIndexConfigModelCustomHint,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(l10n.commonCancel),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(l10n.commonConfirm),
                                          ),
                                        ],
                                      );
                                    },
                                  );

                                  if (ok == true) {
                                    modelController.text = controller.text;
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                    }
                                    setState(() {});
                                  }
                                },
                              ),
                              ListTile(
                                leading: loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                                title: Text(l10n.commonRefresh),
                                onTap: refresh,
                              ),
                              const Divider(height: 1),
                              if (visibleModels.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    l10n.aiLibraryIndexConfigModelEmpty,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              for (final m in visibleModels)
                                ListTile(
                                  title: Text(m),
                                  trailing: (modelController.text.trim() == m)
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () {
                                    modelController.text = m;
                                    Navigator.pop(context);
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              }

              return AlertDialog(
                title: Text(l10n.aiLibraryIndexConfigDialogTitle),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text(l10n.aiLibraryIndexConfigFollowSelectedTitle),
                        subtitle:
                            Text(l10n.aiLibraryIndexConfigFollowSelectedDesc),
                        value: follow,
                        onChanged: (v) {
                          setState(() {
                            follow = v;
                          });
                        },
                      ),
                      if (!follow) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: providerId.trim().isEmpty ? null : providerId,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: l10n.aiLibraryIndexConfigProviderLabel,
                          ),
                          items: eligible
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    Prefs().getAiProviderMeta(id)?.name ?? id,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) {
                            setState(() {
                              providerId = v ?? '';
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: modelController,
                        readOnly: true,
                        onTap: pickEmbeddingModel,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: l10n.aiLibraryIndexConfigModelLabel,
                          hintText: l10n.aiLibraryIndexConfigModelDefaultHint(
                            AiEmbeddingsService.defaultEmbeddingModel,
                          ),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(l10n.aiLibraryIndexConfigChunkSectionTitle),
                        children: [
                          const SizedBox(height: 8),
                          TextField(
                            controller: targetController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText:
                                  l10n.aiLibraryIndexConfigChunkTargetLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: maxController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: l10n.aiLibraryIndexConfigChunkMaxLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: minController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: l10n.aiLibraryIndexConfigChunkMinLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: overlapController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText:
                                  l10n.aiLibraryIndexConfigChunkOverlapLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: maxChapterController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText:
                                  l10n.aiLibraryIndexConfigMaxChapterLabel,
                            ),
                          ),
                        ],
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title:
                            Text(l10n.aiLibraryIndexConfigAdvancedSectionTitle),
                        children: [
                          const SizedBox(height: 8),
                          TextField(
                            controller: batchSizeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: l10n.aiLibraryIndexConfigBatchLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: timeoutController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: l10n.aiLibraryIndexConfigTimeoutLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.aiLibraryIndexConfigChunkHint,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        follow = true;
                        providerId = '';
                        modelController.text = '';
                        targetController.text =
                            AiTextChunker.defaultTargetChars.toString();
                        maxController.text =
                            AiTextChunker.defaultMaxChars.toString();
                        minController.text =
                            AiTextChunker.defaultMinChars.toString();
                        overlapController.text =
                            AiTextChunker.defaultOverlapChars.toString();
                        maxChapterController.text = AiBookIndexer
                            .defaultMaxChapterCharacters
                            .toString();
                        batchSizeController.text =
                            AiBookIndexer.defaultEmbeddingBatchSize.toString();
                        timeoutController.text = '60';
                      });
                    },
                    child: Text(l10n.commonReset),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      final target = parseIntOr(
                        targetController.text,
                        Prefs().aiLibraryIndexChunkTargetChars,
                      );
                      final maxChars = parseIntOr(
                        maxController.text,
                        Prefs().aiLibraryIndexChunkMaxChars,
                      );
                      final minChars = parseIntOr(
                        minController.text,
                        Prefs().aiLibraryIndexChunkMinChars,
                      );
                      final overlap = parseIntOr(
                        overlapController.text,
                        Prefs().aiLibraryIndexChunkOverlapChars,
                      );
                      final maxChapter = parseIntOr(
                        maxChapterController.text,
                        Prefs().aiLibraryIndexMaxChapterCharacters,
                      );

                      final batch = parseIntOr(
                        batchSizeController.text,
                        Prefs().aiLibraryIndexEmbeddingBatchSize,
                      );

                      final timeoutSec = parseIntOr(
                        timeoutController.text,
                        Prefs().aiLibraryIndexEmbeddingsTimeoutSeconds,
                      );

                      Prefs().aiLibraryIndexFollowSelectedProvider = follow;
                      Prefs().aiLibraryIndexProviderId = providerId;
                      Prefs().aiLibraryIndexEmbeddingModel =
                          modelController.text;
                      Prefs().aiLibraryIndexChunkTargetChars = target;
                      Prefs().aiLibraryIndexChunkMaxChars = maxChars;
                      Prefs().aiLibraryIndexChunkMinChars = minChars;
                      Prefs().aiLibraryIndexChunkOverlapChars = overlap;
                      Prefs().aiLibraryIndexMaxChapterCharacters = maxChapter;
                      Prefs().aiLibraryIndexEmbeddingBatchSize = batch;
                      Prefs().aiLibraryIndexEmbeddingsTimeoutSeconds =
                          timeoutSec;

                      Navigator.of(ctx).pop();

                      if (!mounted) return;
                      this.setState(() {
                        _booksFuture =
                            _loadBooks(filter: _filter, token: ++_loadToken);
                      });
                    },
                    child: Text(l10n.commonSave),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      modelController.dispose();
      targetController.dispose();
      maxController.dispose();
      minController.dispose();
      overlapController.dispose();
      maxChapterController.dispose();
      batchSizeController.dispose();
      timeoutController.dispose();
    }
  }

  Widget _buildFilterBar(BuildContext context) {
    final l10n = L10n.of(context);

    Widget chip(_Filter f, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == f,
          onSelected: (_) {
            setState(() {
              _filter = f;
              _selectedBookIds.clear();
            });
            _scheduleBooksRefresh(const Duration(milliseconds: 50));
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        children: [
          chip(_Filter.unindexed, l10n.aiLibraryIndexFilterUnindexed),
          chip(_Filter.expired, l10n.aiLibraryIndexFilterExpired),
          chip(_Filter.indexed, l10n.aiLibraryIndexFilterIndexed),
        ],
      ),
    );
  }

  Widget _buildQueueSection(
    BuildContext context,
    AiLibraryIndexQueueState queue,
    AiLibraryIndexQueueService queueSvc,
  ) {
    final l10n = L10n.of(context);

    final active = queue.activeJob;
    final queuedCount = queue.jobs
        .where((j) => j.status == AiLibraryIndexJobStatus.queued)
        .length;

    final recent = queue.jobs.take(6).toList(growable: false);

    Widget statusText(AiLibraryIndexJob j) {
      String label;
      switch (j.status) {
        case AiLibraryIndexJobStatus.succeeded:
          label = l10n.aiLibraryIndexJobSucceeded;
        case AiLibraryIndexJobStatus.failed:
          label = l10n.aiLibraryIndexJobFailed;
        case AiLibraryIndexJobStatus.cancelled:
          label = l10n.aiLibraryIndexJobCancelled;
        case AiLibraryIndexJobStatus.running:
          label = l10n.aiLibraryIndexQueueRunning;
        case AiLibraryIndexJobStatus.paused:
          label = l10n.aiLibraryIndexQueuePaused;
        case AiLibraryIndexJobStatus.queued:
          label = 'queued';
      }

      final retry =
          j.retryCount > 0 ? '  retry ${j.retryCount}/${j.maxRetries}' : '';

      return Text(
        '$label$retry',
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    Widget errorSummary(AiLibraryIndexJob j) {
      final err = (j.lastError ?? '').trim();
      if (err.isEmpty) return const SizedBox.shrink();
      final firstLine = err.split('\n').first;
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          firstLine,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      l10n.aiLibraryIndexQueueTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    if (queuedCount > 0)
                      Badge(
                        label: Text('$queuedCount'),
                        child: const Icon(Icons.schedule, size: 18),
                      ),
                  ],
                ),
              ),
              if (queue.isPaused)
                Text(
                  l10n.aiLibraryIndexQueuePaused,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              const SizedBox(width: 8),
              if (queue.isPaused)
                OutlinedButton(
                  onPressed: queueSvc.resume,
                  child: Text(l10n.aiLibraryIndexActionResume),
                )
              else
                OutlinedButton(
                  onPressed: queueSvc.pause,
                  child: Text(l10n.aiLibraryIndexActionPause),
                ),
              const SizedBox(width: 8),
              if (active != null) ...[
                OutlinedButton(
                  onPressed: () => queueSvc.cancelJob(active.id),
                  child: Text(l10n.aiLibraryIndexActionCancel),
                ),
                const SizedBox(width: 8),
              ],
              TextButton(
                onPressed: queueSvc.clearFinishedJobs,
                child: Text(l10n.aiLibraryIndexActionClearFinished),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (active == null) ...[
            Text(l10n.aiLibraryIndexQueueEmpty),
          ] else ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: LinearProgressIndicator(
                key: ValueKey(
                    '${active.id}:${active.progress.toStringAsFixed(2)}'),
                value: active.progress.clamp(0, 1),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.aiLibraryIndexQueueRunning}: #${active.bookId}  ${(active.currentChapterTitle ?? '').trim()}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((active.lastError ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                active.lastError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final j in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Book #${j.bookId}',
                              style: Theme.of(context).textTheme.bodyMedium),
                          statusText(j),
                          errorSummary(j),
                        ],
                      ),
                    ),
                    if (j.status == AiLibraryIndexJobStatus.queued ||
                        j.status == AiLibraryIndexJobStatus.running)
                      IconButton(
                        tooltip: l10n.aiLibraryIndexActionCancel,
                        onPressed: () => queueSvc.cancelJob(j.id),
                        icon: const Icon(Icons.cancel_outlined),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBooksSection(BuildContext context) {
    final future = _booksFuture ??
        _loadBooks(
          filter: _filter,
          token: ++_loadToken,
        );
    _booksFuture ??= future;

    return FutureBuilder<List<_BookRow>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <_BookRow>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: SizedBox.shrink(),
          );
        }

        return Column(
          children: [
            for (final r in rows) _buildBookTile(context, r),
          ],
        );
      },
    );
  }

  Widget _buildBookTile(BuildContext context, _BookRow r) {
    final book = r.result.book;
    final selected = _selectedBookIds.contains(book.id);

    IconData statusIcon = Icons.book_outlined;
    Color? statusColor;

    switch (r.status) {
      case _BookIndexStatus.unindexed:
        statusIcon = Icons.radio_button_unchecked;
      case _BookIndexStatus.expired:
        statusIcon = Icons.error_outline;
        statusColor = Theme.of(context).colorScheme.tertiary;
      case _BookIndexStatus.indexed:
        statusIcon = Icons.check_circle_outline;
        statusColor = Theme.of(context).colorScheme.primary;
    }

    final chunkCount = r.indexInfo?.chunkCount ?? 0;

    return ListTile(
      leading: _selecting
          ? Checkbox(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedBookIds.add(book.id);
                  } else {
                    _selectedBookIds.remove(book.id);
                  }
                });
              },
            )
          : Icon(statusIcon, color: statusColor),
      title: Text(book.title),
      subtitle: Text(
        [
          book.author,
          if (!_selecting && chunkCount > 0) 'chunks: $chunkCount',
        ].where((e) => e.trim().isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: _selecting
          ? () {
              setState(() {
                if (selected) {
                  _selectedBookIds.remove(book.id);
                } else {
                  _selectedBookIds.add(book.id);
                }
              });
            }
          : null,
    );
  }

  Future<List<_BookRow>> _loadBooks({
    required _Filter filter,
    required int token,
  }) async {
    final repo = const BooksRepository();
    final aiDb = AiIndexDatabase.instance;

    final results = await repo.searchBooks(limit: _bookListLimit);
    final ids = results.map((e) => e.book.id).toList(growable: false);
    final idx = await aiDb.getBookIndexInfos(ids);

    final providerId = Prefs().aiLibraryIndexProviderIdEffective;
    final embeddingModel = Prefs().aiLibraryIndexEmbeddingModelEffective;
    final chunkTargetChars = Prefs().aiLibraryIndexChunkTargetChars;
    final chunkMaxChars = Prefs().aiLibraryIndexChunkMaxChars;
    final chunkMinChars = Prefs().aiLibraryIndexChunkMinChars;
    final chunkOverlapChars = Prefs().aiLibraryIndexChunkOverlapChars;
    final maxChapterCharacters = Prefs().aiLibraryIndexMaxChapterCharacters;
    final indexVersion = AiBookIndexer.indexAlgorithmVersion;

    _BookIndexStatus classify(BookSearchResult r) {
      final book = r.book;
      final info = idx[book.id];

      if (info == null || info.chunkCount <= 0) {
        return _BookIndexStatus.unindexed;
      }

      final bookMd5 = (book.md5 ?? '').trim();
      final indexedMd5 = (info.bookMd5 ?? '').trim();
      final indexedProvider = (info.providerId ?? '').trim();
      final indexedModel = (info.embeddingModel ?? '').trim();
      final indexedVersion = info.indexVersion ?? 0;

      final indexedChunkTarget =
          info.chunkTargetChars ?? AiTextChunker.defaultTargetChars;
      final indexedChunkMax =
          info.chunkMaxChars ?? AiTextChunker.defaultMaxChars;
      final indexedChunkMin =
          info.chunkMinChars ?? AiTextChunker.defaultMinChars;
      final indexedChunkOverlap =
          info.chunkOverlapChars ?? AiTextChunker.defaultOverlapChars;
      final indexedMaxChapter = info.maxChapterCharacters ??
          AiBookIndexer.defaultMaxChapterCharacters;

      final expired = indexedMd5 != bookMd5 ||
          indexedProvider != providerId ||
          indexedModel != embeddingModel ||
          indexedVersion != indexVersion ||
          indexedChunkTarget != chunkTargetChars ||
          indexedChunkMax != chunkMaxChars ||
          indexedChunkMin != chunkMinChars ||
          indexedChunkOverlap != chunkOverlapChars ||
          indexedMaxChapter != maxChapterCharacters;

      return expired ? _BookIndexStatus.expired : _BookIndexStatus.indexed;
    }

    bool keep(_BookIndexStatus s) => switch (filter) {
          _Filter.unindexed => s == _BookIndexStatus.unindexed,
          _Filter.expired => s == _BookIndexStatus.expired,
          _Filter.indexed => s == _BookIndexStatus.indexed,
        };

    final out = <_BookRow>[];
    for (final r in results) {
      final s = classify(r);
      if (!keep(s)) continue;
      out.add(
        _BookRow(
          result: r,
          status: s,
          indexInfo: idx[r.book.id],
        ),
      );
    }

    // Keep an up-to-date list for Select-all.
    if (token == _loadToken) {
      _currentVisibleBookIds = out.map((e) => e.bookId).toList(growable: false);
    }

    return out;
  }
}
