import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/service/ai/ai_models_service.dart';
import 'package:papertok_reader/service/ai/tools/repository/books_repository.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_text_chunker.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_progress_text.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_service.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
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

typedef AiLibraryBookSearchLoader = Future<List<BookSearchResult>> Function({
  required int limit,
});

typedef AiLibraryBookIndexInfoLoader = Future<Map<int, AiBookIndexInfo>>
    Function(List<int> bookIds);

typedef AiLibraryBookReadinessLoader = Future<AiBookIndexReadiness> Function(
  int bookId,
);

typedef AiLibraryBookBaseEmbeddingRepairer = Future<void> Function(int bookId);
typedef AiLibraryBookGlobalLayerBuilder = Future<void> Function(int bookId);
typedef AiLibraryBookNativeVectorBuilder = Future<void> Function(int bookId);
typedef AiLibraryBookAnnVectorBuilder = Future<void> Function(
  int bookId, {
  void Function(AiVec1VectorIndexBuildProgress progress)? onProgress,
});

enum _BookIndexLayerAction {
  baseEmbeddingRepair,
  globalLayer,
  nativeVector,
  annVector,
}

class _BookIndexLayerActionFailure {
  const _BookIndexLayerActionFailure({
    required this.action,
    required this.message,
  });

  final _BookIndexLayerAction action;
  final String message;
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
  const AiLibraryIndexPage({
    super.key,
    this.bookSearchLoader,
    this.bookIndexInfoLoader,
    this.bookReadinessLoader,
    this.bookBaseEmbeddingRepairer,
    this.bookGlobalLayerBuilder,
    this.bookNativeVectorBuilder,
    this.bookAnnVectorBuilder,
    this.queueStateForTesting,
  });

  final AiLibraryBookSearchLoader? bookSearchLoader;
  final AiLibraryBookIndexInfoLoader? bookIndexInfoLoader;
  final AiLibraryBookReadinessLoader? bookReadinessLoader;
  final AiLibraryBookBaseEmbeddingRepairer? bookBaseEmbeddingRepairer;
  final AiLibraryBookGlobalLayerBuilder? bookGlobalLayerBuilder;
  final AiLibraryBookNativeVectorBuilder? bookNativeVectorBuilder;
  final AiLibraryBookAnnVectorBuilder? bookAnnVectorBuilder;
  final AiLibraryIndexQueueState? queueStateForTesting;

  @override
  ConsumerState<AiLibraryIndexPage> createState() => _AiLibraryIndexPageState();
}

class _AiLibraryIndexPageState extends ConsumerState<AiLibraryIndexPage> {
  static const int _bookListLimit = 200;

  _Filter _filter = _Filter.unindexed;
  bool _selecting = false;
  final Set<int> _selectedBookIds = {};

  Future<List<_BookRow>>? _booksFuture;
  Future<List<AiGlobalIndexBookLayerStatus>>? _globalLayerFuture;
  Future<AiNativeVectorIndexStatus>? _nativeVectorFuture;
  Future<AiVec1VectorIndexStatus>? _annVectorFuture;

  Timer? _refreshDebounce;
  Timer? _activeQueueHeartbeatTimer;
  int _loadToken = 0;
  List<int> _currentVisibleBookIds = const [];
  final Map<int, Future<AiBookIndexReadiness>> _bookReadinessFutures =
      <int, Future<AiBookIndexReadiness>>{};
  final Map<int, _BookIndexLayerActionFailure> _bookLayerActionFailures =
      <int, _BookIndexLayerActionFailure>{};
  final Map<int, AiVec1VectorIndexBuildProgress> _bookAnnVectorProgress =
      <int, AiVec1VectorIndexBuildProgress>{};
  final Set<int> _globalLayerBookBuildingIds = <int>{};
  final Set<int> _baseEmbeddingRepairBookIds = <int>{};
  final Set<int> _nativeVectorBookBuildingIds = <int>{};
  final Set<int> _annVectorBookBuildingIds = <int>{};
  bool _globalLayerBackfilling = false;
  bool _globalLayerCancelRequested = false;
  AiGlobalIndexBackfillProgress? _globalLayerProgress;
  bool _nativeVectorBackfilling = false;
  bool _nativeVectorCancelRequested = false;
  AiNativeVectorBackfillProgress? _nativeVectorProgress;
  bool _annVectorBuilding = false;
  bool _annVectorCancelRequested = false;
  AiVec1VectorIndexBuildProgress? _annVectorProgress;

  @override
  void initState() {
    super.initState();

    _booksFuture = _loadBooks(filter: _filter, token: ++_loadToken);
    _globalLayerFuture = _loadMissingGlobalLayers();
    _nativeVectorFuture = _loadNativeVectorStatus();
    _annVectorFuture = _loadAnnVectorStatus();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _activeQueueHeartbeatTimer?.cancel();
    super.dispose();
  }

  void _scheduleBooksRefresh(Duration debounce) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(debounce, () {
      if (!mounted) return;
      setState(() {
        _bookReadinessFutures.clear();
        _booksFuture = _loadBooks(filter: _filter, token: ++_loadToken);
        _globalLayerFuture = _loadMissingGlobalLayers();
        _nativeVectorFuture = _loadNativeVectorStatus();
        _annVectorFuture = _loadAnnVectorStatus();
      });
    });
  }

  void _syncActiveQueueHeartbeatTimer(bool shouldRun) {
    if (!shouldRun) {
      _activeQueueHeartbeatTimer?.cancel();
      _activeQueueHeartbeatTimer = null;
      return;
    }
    _activeQueueHeartbeatTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final AiLibraryIndexQueueState queue =
        widget.queueStateForTesting ?? ref.watch(aiLibraryIndexQueueProvider);
    final queueSvc = widget.queueStateForTesting == null
        ? ref.read(aiLibraryIndexQueueProvider.notifier)
        : null;
    _syncActiveQueueHeartbeatTimer(queue.activeJob != null);

    // The queue updates fairly frequently (progress), so debounce book list
    // refreshes to avoid jitter. Must live in build (not initState) per
    // Riverpod's `ref.listen` contract.
    if (widget.queueStateForTesting == null) {
      ref.listen<AiLibraryIndexQueueState>(aiLibraryIndexQueueProvider,
          (prev, next) {
        _scheduleBooksRefresh(const Duration(milliseconds: 900));
      });
    }

    return SettingsSubpageScaffold(
      title: l10n.settingsAiLibraryIndexTitle,
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
                        onPressed: _selectedBookIds.isEmpty || queueSvc == null
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
          : _buildQueueBottomProgress(context, queue),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate.fixed(
                [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      l10n.settingsAiLibraryIndexSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  _buildConfigTile(context),
                  _buildGlobalLayerTile(context),
                  _buildNativeVectorTile(context),
                  _buildAnnVectorTile(context),
                  _buildFilterBar(context),
                  const Divider(height: 1),
                  _buildQueueSection(context, queue, queueSvc),
                  const Divider(height: 1),
                ],
              ),
            ),
            _buildBooksSection(context, queue, queueSvc),
          ],
        ),
      ),
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
    final rerankEnabled = Prefs().aiLibraryIndexRerankEnabled;
    final rerankProviderId = Prefs().aiLibraryIndexRerankProviderIdEffective;
    final rerankProviderName =
        Prefs().getAiProviderMeta(rerankProviderId)?.name ?? rerankProviderId;
    final rerankModel = Prefs().aiLibraryIndexRerankModelEffective;
    final retryCount = Prefs().aiLibraryIndexQueueMaxRetries;

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
    final line3 = '${_retrySummaryText(context, retryCount)} · '
        '${_rerankSummaryText(
      context,
      enabled: rerankEnabled,
      mode: Prefs().aiLibraryIndexRerankMode,
      providerName: rerankProviderName,
      model: rerankModel,
    )}';

    return ListTile(
      leading: const Icon(Icons.tune),
      title: Text(l10n.aiLibraryIndexConfigTitle),
      subtitle: Text('$line1\n$line2\n$line3'),
      isThreeLine: true,
      onTap: () => _showIndexConfigDialog(context),
    );
  }

  Future<List<AiGlobalIndexBookLayerStatus>> _loadMissingGlobalLayers() {
    return AiGlobalIndexBuilder().listBooksMissingGlobalLayer(
      limit: _bookListLimit * 10,
    );
  }

  Future<AiNativeVectorIndexStatus> _loadNativeVectorStatus() async {
    final db = await AiIndexDatabase.instance.database;
    return const AiNativeVectorIndexBuilder().inspectIndexedBooks(db);
  }

  Future<AiVec1VectorIndexStatus> _loadAnnVectorStatus() async {
    final db = await AiIndexDatabase.instance.database;
    return const AiVec1VectorIndexBuilder().inspectBuildStatus(db);
  }

  Widget _buildGlobalLayerTile(BuildContext context) {
    final l10n = L10n.of(context);
    final future = _globalLayerFuture ?? _loadMissingGlobalLayers();
    _globalLayerFuture ??= future;

    return FutureBuilder<List<AiGlobalIndexBookLayerStatus>>(
      future: future,
      builder: (context, snapshot) {
        final missing = snapshot.data ?? const <AiGlobalIndexBookLayerStatus>[];
        final missingCount = missing.length;
        final progress = _globalLayerProgress;
        final subtitle = _globalLayerBackfilling && progress != null
            ? l10n.aiLibraryIndexGlobalLayerRunning(
                progress.done,
                progress.total,
              )
            : snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null
                ? l10n.aiLibraryIndexGlobalLayerChecking
                : missingCount <= 0
                    ? l10n.aiLibraryIndexGlobalLayerReady
                    : l10n.aiLibraryIndexGlobalLayerMissing(missingCount);

        return ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(l10n.aiLibraryIndexGlobalLayerTitle),
          subtitle: Text(
            '${l10n.aiLibraryIndexGlobalLayerDesc}\n$subtitle',
          ),
          isThreeLine: true,
          trailing: _globalLayerBackfilling
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _globalLayerCancelRequested
                          ? null
                          : () => setState(
                                () => _globalLayerCancelRequested = true,
                              ),
                      child: Text(l10n.aiLibraryIndexGlobalLayerCancel),
                    ),
                  ],
                )
              : TextButton(
                  onPressed: missingCount <= 0
                      ? null
                      : () => unawaited(_backfillGlobalLayers()),
                  child: Text(l10n.aiLibraryIndexGlobalLayerAction),
                ),
        );
      },
    );
  }

  Future<void> _backfillGlobalLayers() async {
    if (_globalLayerBackfilling) return;
    final l10n = L10n.of(context);

    setState(() {
      _globalLayerBackfilling = true;
      _globalLayerCancelRequested = false;
      _globalLayerProgress = null;
    });

    try {
      final result = await AiGlobalIndexBuilder().backfillMissingGlobalLayers(
        limit: _bookListLimit * 10,
        shouldCancel: () => _globalLayerCancelRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _globalLayerProgress = progress);
        },
      );
      if (!mounted) return;

      if (result.cancelled) {
        AnxToast.show(
          l10n.aiLibraryIndexGlobalLayerCancelled(
            result.rebuiltBookIds.length,
            result.totalCandidates,
          ),
        );
      } else {
        AnxToast.show(
          l10n.aiLibraryIndexGlobalLayerDone(
            result.rebuiltBookIds.length,
            result.failedBookIds.length,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      AnxToast.show(l10n.aiLibraryIndexGlobalLayerFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _globalLayerBackfilling = false;
          _globalLayerCancelRequested = false;
          _globalLayerProgress = null;
          _bookReadinessFutures.clear();
          _booksFuture = _loadBooks(filter: _filter, token: ++_loadToken);
          _globalLayerFuture = _loadMissingGlobalLayers();
        });
      }
    }
  }

  Widget _buildNativeVectorTile(BuildContext context) {
    final l10n = L10n.of(context);
    final future = _nativeVectorFuture ?? _loadNativeVectorStatus();
    _nativeVectorFuture ??= future;

    return FutureBuilder<AiNativeVectorIndexStatus>(
      future: future,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final progress = _nativeVectorProgress;
        final subtitle = _nativeVectorBackfilling && progress != null
            ? _nativeVectorRunningText(context, progress)
            : snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null
                ? _nativeVectorCheckingText(context)
                : _nativeVectorStatusText(context, status);
        final canBackfill = !_nativeVectorBackfilling &&
            status != null &&
            status.missingBookCount > 0;

        return ListTile(
          leading: const Icon(Icons.speed_outlined),
          title: Text(_nativeVectorTitle(context)),
          subtitle: Text('${_nativeVectorDesc(context)}\n$subtitle'),
          isThreeLine: true,
          trailing: _nativeVectorBackfilling
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _nativeVectorCancelRequested
                          ? null
                          : () => setState(
                                () => _nativeVectorCancelRequested = true,
                              ),
                      child: Text(l10n.commonCancel),
                    ),
                  ],
                )
              : TextButton(
                  onPressed: canBackfill
                      ? () => unawaited(_backfillNativeVectors())
                      : null,
                  child: Text(_nativeVectorAction(context)),
                ),
        );
      },
    );
  }

  Future<void> _backfillNativeVectors() async {
    if (_nativeVectorBackfilling) return;

    setState(() {
      _nativeVectorBackfilling = true;
      _nativeVectorCancelRequested = false;
      _nativeVectorProgress = null;
    });

    try {
      final db = await AiIndexDatabase.instance.database;
      final result =
          await const AiNativeVectorIndexBuilder().backfillIndexedBooks(
        db,
        shouldCancel: () => _nativeVectorCancelRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _nativeVectorProgress = progress);
        },
      );
      if (!mounted) return;

      AnxToast.show(
        result.cancelled
            ? _nativeVectorCancelledToast(context, result)
            : _nativeVectorDoneToast(context, result),
      );
    } catch (e) {
      if (!mounted) return;
      AnxToast.show(_nativeVectorFailedToast(context, e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _nativeVectorBackfilling = false;
          _nativeVectorCancelRequested = false;
          _nativeVectorProgress = null;
          _bookReadinessFutures.clear();
          _nativeVectorFuture = _loadNativeVectorStatus();
          _annVectorFuture = _loadAnnVectorStatus();
        });
      }
    }
  }

  Widget _buildAnnVectorTile(BuildContext context) {
    final l10n = L10n.of(context);
    final future = _annVectorFuture ?? _loadAnnVectorStatus();
    _annVectorFuture ??= future;

    return FutureBuilder<AiVec1VectorIndexStatus>(
      future: future,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final progress = _annVectorProgress;
        final subtitle = _annVectorBuilding && progress != null
            ? _annVectorRunningText(context, progress)
            : snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null
                ? _annVectorCheckingText(context)
                : _annVectorStatusText(context, status);
        final canBuild =
            !_annVectorBuilding && status != null && status.canBuild;

        return ListTile(
          leading: const Icon(Icons.hub_outlined),
          title: Text(_annVectorTitle(context)),
          subtitle: Text('${_annVectorDesc(context)}\n$subtitle'),
          isThreeLine: true,
          trailing: _annVectorBuilding
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _annVectorCancelRequested
                          ? null
                          : () => setState(
                                () => _annVectorCancelRequested = true,
                              ),
                      child: Text(l10n.commonCancel),
                    ),
                  ],
                )
              : TextButton(
                  onPressed:
                      canBuild ? () => unawaited(_buildAnnVectors()) : null,
                  child: Text(_annVectorAction(context)),
                ),
        );
      },
    );
  }

  Future<void> _buildAnnVectors() async {
    if (_annVectorBuilding) return;

    setState(() {
      _annVectorBuilding = true;
      _annVectorCancelRequested = false;
      _annVectorProgress = null;
    });

    try {
      final db = await AiIndexDatabase.instance.database;
      final result =
          await const AiVec1VectorIndexBuilder().rebuildFromNativeShadowRows(
        db,
        shouldCancel: () => _annVectorCancelRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _annVectorProgress = progress);
        },
      );
      if (!mounted) return;

      AnxToast.show(
        result.cancelled
            ? _annVectorCancelledToast(context, result)
            : result.available
                ? _annVectorDoneToast(context, result)
                : _annVectorUnavailableToast(context, result.lastError),
      );
    } catch (e) {
      if (!mounted) return;
      AnxToast.show(_annVectorFailedToast(context, e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _annVectorBuilding = false;
          _annVectorCancelRequested = false;
          _annVectorProgress = null;
          _bookReadinessFutures.clear();
          _annVectorFuture = _loadAnnVectorStatus();
        });
      }
    }
  }

  bool _isZh(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh';
  }

  String _nativeVectorTitle(BuildContext context) =>
      _isZh(context) ? '向量索引升级' : 'Native vector index';

  String _nativeVectorDesc(BuildContext context) => _isZh(context)
      ? '把旧索引里的 Embedding 转成紧凑向量层；不重嵌入，给 sqlite-vec/ANN 后端做准备。'
      : 'Convert existing embeddings into a compact vector layer without re-embedding, ready for sqlite-vec/ANN backends.';

  String _nativeVectorCheckingText(BuildContext context) =>
      _isZh(context) ? '正在检查向量层状态...' : 'Checking vector layer status...';

  String _nativeVectorAction(BuildContext context) =>
      _isZh(context) ? '升级' : 'Upgrade';

  String _nativeVectorStatusText(
    BuildContext context,
    AiNativeVectorIndexStatus? status,
  ) {
    if (status == null) return _nativeVectorCheckingText(context);
    if (status.indexedBookCount <= 0) {
      return _isZh(context)
          ? '还没有已完成的书库索引。'
          : 'No completed library indexes yet.';
    }
    if (status.missingBookCount <= 0) {
      return _isZh(context)
          ? '所有已索引书籍都已有向量层；${status.vectorRowCount} 行可用于 native 检索。'
          : 'All indexed books have vector rows; ${status.vectorRowCount} rows are ready for native retrieval.';
    }
    return _isZh(context)
        ? '${status.missingBookCount} 本旧索引书籍可升级；完整准备 ${status.readyBookCount}/${status.indexedBookCount} 本。'
        : '${status.missingBookCount} old indexed book(s) can be upgraded; ${status.readyBookCount}/${status.indexedBookCount} fully ready.';
  }

  String _nativeVectorRunningText(
    BuildContext context,
    AiNativeVectorBackfillProgress progress,
  ) {
    return _isZh(context)
        ? '正在升级向量层 ${progress.done}/${progress.total} · 写入 ${progress.rowsWritten} 行'
        : 'Upgrading vector layer ${progress.done}/${progress.total} · ${progress.rowsWritten} rows written';
  }

  String _nativeVectorDoneToast(
    BuildContext context,
    AiNativeVectorIndexedBooksBackfillResult result,
  ) {
    return _isZh(context)
        ? '向量索引升级完成：处理 ${result.booksProcessed} 本，写入 ${result.rowsWritten} 行。'
        : 'Vector index upgraded: ${result.booksProcessed} book(s), ${result.rowsWritten} row(s) written.';
  }

  String _nativeVectorCancelledToast(
    BuildContext context,
    AiNativeVectorIndexedBooksBackfillResult result,
  ) {
    return _isZh(context)
        ? '向量索引升级已取消：完成 ${result.booksProcessed}/${result.totalCandidates} 本。'
        : 'Vector index upgrade cancelled after ${result.booksProcessed}/${result.totalCandidates} book(s).';
  }

  String _nativeVectorFailedToast(BuildContext context, String message) =>
      _isZh(context)
          ? '向量索引升级失败：$message'
          : 'Vector index upgrade failed: $message';

  String _annVectorTitle(BuildContext context) =>
      _isZh(context) ? 'ANN 向量索引' : 'ANN vector index';

  String _annVectorDesc(BuildContext context) => _isZh(context)
      ? '用紧凑向量层构建 Vec1/sqlite-vec ANN 表；有扩展时用于主语义召回，没有扩展时自动降级。'
      : 'Build Vec1/sqlite-vec ANN tables from compact vectors for primary semantic recall when the extension is available.';

  String _annVectorCheckingText(BuildContext context) =>
      _isZh(context) ? '正在检查 ANN 状态...' : 'Checking ANN status...';

  String _annVectorAction(BuildContext context) =>
      _isZh(context) ? '构建' : 'Build';

  String _annVectorStatusText(
    BuildContext context,
    AiVec1VectorIndexStatus? status,
  ) {
    if (status == null) return _annVectorCheckingText(context);
    if (!status.available) {
      final reason = status.lastError;
      return _isZh(context)
          ? '当前数据库未加载 Vec1/sqlite-vec 扩展，ANN 暂不可用${reason == null ? '' : '：$reason'}'
          : 'Vec1/sqlite-vec is not loaded, so ANN is unavailable${reason == null ? '' : ': $reason'}';
    }
    if (status.nativeRowCount <= 0) {
      return _isZh(context)
          ? '还没有可构建 ANN 的向量层；请先运行“向量索引升级”。'
          : 'No compact vector rows are ready yet. Run Native vector index first.';
    }
    if (status.missingGroupCount <= 0 && status.missingBookTableCount <= 0) {
      return _isZh(context)
          ? 'ANN 已就绪：${status.readyGroups}/${status.totalGroups} 组，单书 sidecar ${status.readyBookTables}/${status.totalBookTables} 本，${status.annRowCount}/${status.nativeRowCount} 全局行，${status.bookAnnRowCount}/${status.nativeRowCount} sidecar 行。'
          : 'ANN ready: ${status.readyGroups}/${status.totalGroups} group(s), ${status.readyBookTables}/${status.totalBookTables} book sidecar(s), ${status.annRowCount}/${status.nativeRowCount} global row(s), ${status.bookAnnRowCount}/${status.nativeRowCount} sidecar row(s).';
    }
    return _isZh(context)
        ? '可构建 ANN：缺 ${status.missingGroupCount}/${status.totalGroups} 组，缺单书 sidecar ${status.missingBookTableCount}/${status.totalBookTables} 本，已写 ${status.annRowCount}/${status.nativeRowCount} 全局行，${status.bookAnnRowCount}/${status.nativeRowCount} sidecar 行。'
        : 'ANN can be built: ${status.missingGroupCount}/${status.totalGroups} group(s) missing, ${status.missingBookTableCount}/${status.totalBookTables} book sidecar(s) missing, ${status.annRowCount}/${status.nativeRowCount} global row(s), ${status.bookAnnRowCount}/${status.nativeRowCount} sidecar row(s) written.';
  }

  String _annVectorRunningText(
    BuildContext context,
    AiVec1VectorIndexBuildProgress progress,
  ) {
    return _isZh(context)
        ? '正在构建 ANN ${progress.done}/${progress.total} · 写入 ${progress.rowsWritten} 行'
        : 'Building ANN ${progress.done}/${progress.total} · ${progress.rowsWritten} rows written';
  }

  String _annVectorDoneToast(
    BuildContext context,
    AiVec1VectorIndexBuildResult result,
  ) {
    return _isZh(context)
        ? 'ANN 构建完成：${result.tablesBuilt}/${result.totalGroups} 组，写入 ${result.rowsWritten} 行。'
        : 'ANN built: ${result.tablesBuilt}/${result.totalGroups} group(s), ${result.rowsWritten} row(s) written.';
  }

  String _annVectorCancelledToast(
    BuildContext context,
    AiVec1VectorIndexBuildResult result,
  ) {
    return _isZh(context)
        ? 'ANN 构建已取消：完成 ${result.tablesBuilt}/${result.totalGroups} 组，写入 ${result.rowsWritten} 行。'
        : 'ANN build cancelled after ${result.tablesBuilt}/${result.totalGroups} group(s), ${result.rowsWritten} row(s) written.';
  }

  String _annVectorUnavailableToast(BuildContext context, String? message) =>
      _isZh(context)
          ? 'ANN 暂不可用：${message ?? '未检测到 Vec1/sqlite-vec 扩展'}'
          : 'ANN unavailable: ${message ?? 'Vec1/sqlite-vec extension was not detected'}';

  String _annVectorFailedToast(BuildContext context, String message) =>
      _isZh(context) ? 'ANN 构建失败：$message' : 'ANN build failed: $message';

  String _rerankSummaryText(
    BuildContext context, {
    required bool enabled,
    required String mode,
    required String providerName,
    required String model,
  }) {
    final zh = _isZh(context);
    if (!enabled) return zh ? '重排：关闭' : 'Rerank: off';
    final modeLabel = mode == 'llm'
        ? (zh ? 'LLM 结构化重排' : 'LLM structured reranker')
        : (zh ? '专用 HTTP 重排模型' : 'Dedicated HTTP reranker');
    return zh
        ? '重排：$modeLabel · $providerName · $model'
        : 'Rerank: $modeLabel · $providerName · $model';
  }

  String _retrySummaryText(BuildContext context, int retryCount) {
    final zh = _isZh(context);
    return zh ? '失败重试：$retryCount 次' : 'Retries: $retryCount';
  }

  String _rerankEnabledTitle(BuildContext context) =>
      _isZh(context) ? '启用重排模型' : 'Enable reranker';

  String _rerankEnabledDesc(BuildContext context) => _isZh(context)
      ? '在混合检索之后使用重排模型重新排序候选结果。'
      : 'Use a rerank model after hybrid retrieval.';

  String _rerankModeLabel(BuildContext context) =>
      _isZh(context) ? '重排模式' : 'Rerank mode';

  String _rerankModeHttpLabel(BuildContext context) =>
      _isZh(context) ? '专用 HTTP 重排模型' : 'Dedicated HTTP reranker';

  String _rerankModeLlmLabel(BuildContext context) =>
      _isZh(context) ? 'LLM 结构化重排' : 'LLM structured reranker';

  String _rerankFollowProviderTitle(BuildContext context) =>
      _isZh(context) ? '跟随索引供应商' : 'Follow index provider';

  String _rerankFollowProviderDesc(BuildContext context) => _isZh(context)
      ? '使用与 Embedding 索引相同的供应商配置。'
      : 'Use the same provider configured for embeddings.';

  String _rerankProviderLabel(BuildContext context) =>
      _isZh(context) ? '重排供应商' : 'Rerank provider';

  String _rerankModelLabel(BuildContext context) =>
      _isZh(context) ? '重排模型' : 'Rerank model';

  String _rerankInstructionLabel(BuildContext context) =>
      _isZh(context) ? '重排指令' : 'Rerank instruction';

  String _rerankCandidatesLabel(BuildContext context) =>
      _isZh(context) ? '重排候选数量' : 'Rerank candidates';

  String _rerankDocumentCharsLabel(BuildContext context) =>
      _isZh(context) ? '重排文档字符数' : 'Rerank document chars';

  String _rerankTimeoutLabel(BuildContext context) =>
      _isZh(context) ? '重排超时（秒）' : 'Rerank timeout (sec)';

  String _retryCountLabel(BuildContext context) =>
      _isZh(context) ? '失败重试次数' : 'Failed job retries';

  Future<void> _showIndexConfigDialog(BuildContext context) async {
    final l10n = L10n.of(context);

    var follow = Prefs().aiLibraryIndexFollowSelectedProvider;
    var providerId = Prefs().aiLibraryIndexProviderId;
    var rerankEnabled = Prefs().aiLibraryIndexRerankEnabled;
    var rerankMode = Prefs().aiLibraryIndexRerankMode;
    var rerankFollow = Prefs().aiLibraryIndexRerankFollowIndexProvider;
    var rerankProviderId = Prefs().aiLibraryIndexRerankProviderId;

    final modelController = TextEditingController(
      text: Prefs().aiLibraryIndexEmbeddingModel.trim(),
    );
    final rerankModelController = TextEditingController(
      text: Prefs().aiLibraryIndexRerankModel.trim(),
    );
    final rerankInstructionController = TextEditingController(
      text: Prefs().aiLibraryIndexRerankInstruction.trim(),
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
    final retryController = TextEditingController(
      text: Prefs().aiLibraryIndexQueueMaxRetries.toString(),
    );
    final rerankMaxCandidatesController = TextEditingController(
      text: Prefs().aiLibraryIndexRerankMaxCandidates.toString(),
    );
    final rerankMaxDocumentCharsController = TextEditingController(
      text: Prefs().aiLibraryIndexRerankMaxDocumentChars.toString(),
    );
    final rerankTimeoutController = TextEditingController(
      text: Prefs().aiLibraryIndexRerankTimeoutSeconds.toString(),
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
              if (!eligible.contains(rerankProviderId)) {
                rerankProviderId = eligible.isEmpty ? '' : eligible.first;
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
                          initialValue:
                              providerId.trim().isEmpty ? null : providerId,
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
                          TextField(
                            controller: retryController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: _retryCountLabel(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_rerankEnabledTitle(context)),
                            subtitle: Text(_rerankEnabledDesc(context)),
                            value: rerankEnabled,
                            onChanged: (v) {
                              setState(() {
                                rerankEnabled = v;
                              });
                            },
                          ),
                          if (rerankEnabled) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: rerankMode,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankModeLabel(context),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'http',
                                  child: Text(_rerankModeHttpLabel(context)),
                                ),
                                DropdownMenuItem(
                                  value: 'llm',
                                  child: Text(_rerankModeLlmLabel(context)),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  rerankMode = v ?? 'http';
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_rerankFollowProviderTitle(context)),
                              subtitle:
                                  Text(_rerankFollowProviderDesc(context)),
                              value: rerankFollow,
                              onChanged: (v) {
                                setState(() {
                                  rerankFollow = v;
                                });
                              },
                            ),
                            if (!rerankFollow) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: rerankProviderId.trim().isEmpty
                                    ? null
                                    : rerankProviderId,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: _rerankProviderLabel(context),
                                ),
                                items: eligible
                                    .map(
                                      (id) => DropdownMenuItem(
                                        value: id,
                                        child: Text(
                                          Prefs().getAiProviderMeta(id)?.name ??
                                              id,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (v) {
                                  setState(() {
                                    rerankProviderId = v ?? '';
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 8),
                            TextField(
                              controller: rerankModelController,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankModelLabel(context),
                                hintText: 'Qwen/Qwen3-Reranker-8B',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: rerankInstructionController,
                              minLines: 1,
                              maxLines: 3,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankInstructionLabel(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: rerankMaxCandidatesController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankCandidatesLabel(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: rerankMaxDocumentCharsController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankDocumentCharsLabel(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: rerankTimeoutController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: _rerankTimeoutLabel(context),
                              ),
                            ),
                          ],
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
                        rerankEnabled = false;
                        rerankMode = 'http';
                        rerankFollow = true;
                        rerankProviderId = '';
                        modelController.text = '';
                        rerankModelController.text = '';
                        rerankInstructionController.text = '';
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
                        retryController.text = '3';
                        rerankMaxCandidatesController.text = '40';
                        rerankMaxDocumentCharsController.text = '1800';
                        rerankTimeoutController.text = '20';
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
                      final retryCount = parseIntOr(
                        retryController.text,
                        Prefs().aiLibraryIndexQueueMaxRetries,
                      );
                      final rerankMaxCandidates = parseIntOr(
                        rerankMaxCandidatesController.text,
                        Prefs().aiLibraryIndexRerankMaxCandidates,
                      );
                      final rerankMaxDocumentChars = parseIntOr(
                        rerankMaxDocumentCharsController.text,
                        Prefs().aiLibraryIndexRerankMaxDocumentChars,
                      );
                      final rerankTimeoutSec = parseIntOr(
                        rerankTimeoutController.text,
                        Prefs().aiLibraryIndexRerankTimeoutSeconds,
                      );

                      Prefs().aiLibraryIndexFollowSelectedProvider = follow;
                      Prefs().aiLibraryIndexProviderId = providerId;
                      Prefs().aiLibraryIndexEmbeddingModel =
                          modelController.text;
                      Prefs().aiLibraryIndexRerankEnabled = rerankEnabled;
                      Prefs().aiLibraryIndexRerankMode = rerankMode;
                      Prefs().aiLibraryIndexRerankFollowIndexProvider =
                          rerankFollow;
                      Prefs().aiLibraryIndexRerankProviderId = rerankProviderId;
                      Prefs().aiLibraryIndexRerankModel =
                          rerankModelController.text;
                      Prefs().aiLibraryIndexRerankInstruction =
                          rerankInstructionController.text;
                      Prefs().aiLibraryIndexRerankMaxCandidates =
                          rerankMaxCandidates;
                      Prefs().aiLibraryIndexRerankMaxDocumentChars =
                          rerankMaxDocumentChars;
                      Prefs().aiLibraryIndexRerankTimeoutSeconds =
                          rerankTimeoutSec;
                      Prefs().aiLibraryIndexChunkTargetChars = target;
                      Prefs().aiLibraryIndexChunkMaxChars = maxChars;
                      Prefs().aiLibraryIndexChunkMinChars = minChars;
                      Prefs().aiLibraryIndexChunkOverlapChars = overlap;
                      Prefs().aiLibraryIndexMaxChapterCharacters = maxChapter;
                      Prefs().aiLibraryIndexEmbeddingBatchSize = batch;
                      Prefs().aiLibraryIndexEmbeddingsTimeoutSeconds =
                          timeoutSec;
                      Prefs().aiLibraryIndexQueueMaxRetries = retryCount;

                      Navigator.of(ctx).pop();

                      if (!mounted) return;
                      this.setState(() {
                        _bookReadinessFutures.clear();
                        _booksFuture =
                            _loadBooks(filter: _filter, token: ++_loadToken);
                        _globalLayerFuture = _loadMissingGlobalLayers();
                        _nativeVectorFuture = _loadNativeVectorStatus();
                        _annVectorFuture = _loadAnnVectorStatus();
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
      rerankModelController.dispose();
      rerankInstructionController.dispose();
      targetController.dispose();
      maxController.dispose();
      minController.dispose();
      overlapController.dispose();
      maxChapterController.dispose();
      batchSizeController.dispose();
      timeoutController.dispose();
      retryController.dispose();
      rerankMaxCandidatesController.dispose();
      rerankMaxDocumentCharsController.dispose();
      rerankTimeoutController.dispose();
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
              _bookReadinessFutures.clear();
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
    AiLibraryIndexQueueService? queueSvc,
  ) {
    final l10n = L10n.of(context);

    final active = queue.activeJob;
    final queuedCount = queue.queuedJobCount;
    final totalCount = queue.totalJobCount;

    final recent = queue.jobs.take(6).toList(growable: false);
    final activeHeartbeat =
        active == null ? '' : _jobHeartbeatText(context, active);
    final activeDetail =
        active == null ? '' : _jobProgressDetailText(context, active);

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
          label = _localizedQueuedLabel(context);
      }

      final retry = j.retryCount > 0
          ? '  ${_localizedRetryLabel(context, j.retryCount, j.maxRetries)}'
          : '';
      final progress = j.status == AiLibraryIndexJobStatus.running ||
              j.status == AiLibraryIndexJobStatus.paused
          ? '  ${_formatPercent(j.progress)}'
          : '';
      final detail = _jobProgressDetailText(context, j);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label$progress$retry',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
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
                  onPressed: queueSvc?.resume,
                  child: Text(l10n.aiLibraryIndexActionResume),
                )
              else
                OutlinedButton(
                  onPressed: queueSvc?.pause,
                  child: Text(l10n.aiLibraryIndexActionPause),
                ),
              const SizedBox(width: 8),
              if (active != null) ...[
                OutlinedButton(
                  onPressed: queueSvc == null
                      ? null
                      : () => queueSvc.cancelJob(active.id),
                  child: Text(l10n.aiLibraryIndexActionCancel),
                ),
                const SizedBox(width: 8),
              ],
              TextButton(
                onPressed: queueSvc?.clearFinishedJobs,
                child: Text(l10n.aiLibraryIndexActionClearFinished),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (totalCount > 0) ...[
            Text(
              _queueSummaryText(context, queue),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: queue.overallProgress),
            const SizedBox(height: 8),
          ],
          if (active == null) ...[
            Text(
              totalCount == 0
                  ? l10n.aiLibraryIndexQueueEmpty
                  : _queueIdleText(context, queue),
            ),
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
              '${l10n.aiLibraryIndexQueueRunning}: '
              '${_localizedBookLabel(context, active.bookId)}  '
              '${_formatPercent(active.progress)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (activeHeartbeat.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                activeHeartbeat,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (activeDetail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                activeDetail,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
                        onPressed: queueSvc == null
                            ? null
                            : () => queueSvc.cancelJob(j.id),
                        icon: const Icon(Icons.cancel_outlined),
                      )
                    else if (j.status == AiLibraryIndexJobStatus.failed ||
                        j.status == AiLibraryIndexJobStatus.cancelled)
                      IconButton(
                        tooltip: _localizedRetryActionLabel(context),
                        onPressed: queueSvc == null
                            ? null
                            : () => queueSvc.retryJob(j.id),
                        icon: const Icon(Icons.replay_outlined),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBooksSection(
    BuildContext context,
    AiLibraryIndexQueueState queue,
    AiLibraryIndexQueueService? queueSvc,
  ) {
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
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (rows.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: SizedBox.shrink(),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildBookTile(
              context,
              rows[index],
              queue,
              queueSvc,
            ),
            childCount: rows.length,
          ),
        );
      },
    );
  }

  Widget? _buildQueueBottomProgress(
    BuildContext context,
    AiLibraryIndexQueueState queue,
  ) {
    if (queue.totalJobCount == 0) return null;
    if (queue.queuedJobCount == 0 &&
        queue.runningJobCount == 0 &&
        queue.pausedJobCount == 0) {
      return null;
    }

    final theme = Theme.of(context);
    final active = queue.activeJob;

    return SafeArea(
      top: false,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: queue.overallProgress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    queue.isPaused
                        ? Icons.pause_circle_outline
                        : Icons.auto_awesome_motion_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      active == null
                          ? _queueSummaryText(context, queue)
                          : _compactActiveQueueText(context, active),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (active != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatPercent(active.progress),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _queueSummaryText(
    BuildContext context,
    AiLibraryIndexQueueState queue,
  ) {
    final code = Localizations.localeOf(context).languageCode;
    final percent = _formatPercent(queue.overallProgress);
    if (code == 'zh') {
      return '队列处理 $percent · 已处理 ${queue.finishedJobCount}/${queue.totalJobCount} · '
          '等待 ${queue.queuedJobCount} · 失败 ${queue.failedJobCount}';
    }
    return 'Queue $percent · handled ${queue.finishedJobCount}/${queue.totalJobCount} · '
        'waiting ${queue.queuedJobCount} · failed ${queue.failedJobCount}';
  }

  String _compactActiveQueueText(
    BuildContext context,
    AiLibraryIndexJob job,
  ) {
    return AiLibraryIndexProgressText.compact(
      job: job,
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  String _jobProgressDetailText(
    BuildContext context,
    AiLibraryIndexJob job,
  ) {
    return AiLibraryIndexProgressText.detail(
      job: job,
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  String _jobHeartbeatText(BuildContext context, AiLibraryIndexJob job) {
    final updatedAt = job.updatedAt;
    if (updatedAt == null) return '';
    return _localizedLastUpdateText(context, updatedAt);
  }

  String _localizedBookLabel(BuildContext context, int bookId) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '书籍 #$bookId'
        : 'Book #$bookId';
  }

  String _localizedLastUpdateText(BuildContext context, int updatedAtMs) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );

    String ageText;
    if (age.inSeconds < 30) {
      ageText = zh ? '刚刚' : 'just now';
    } else if (age.inMinutes < 1) {
      ageText = zh ? '${age.inSeconds} 秒前' : '${age.inSeconds}s ago';
    } else if (age.inHours < 1) {
      ageText = zh ? '${age.inMinutes} 分钟前' : '${age.inMinutes}m ago';
    } else {
      ageText = zh ? '${age.inHours} 小时前' : '${age.inHours}h ago';
    }

    final stale = age.inMinutes >= 3;
    if (zh) {
      return stale ? '最后更新 $ageText（无新进度）' : '最后更新 $ageText';
    }
    return stale
        ? 'last update $ageText (no new progress)'
        : 'last update $ageText';
  }

  String _localizedQueuedLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '等待中'
        : 'Queued';
  }

  String _queueIdleText(BuildContext context, AiLibraryIndexQueueState queue) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (queue.queuedJobCount > 0) {
      if (queue.isPaused) {
        return zh ? '已暂停，等待继续处理' : 'Paused, waiting to continue';
      }
      return zh ? '准备继续处理' : 'Ready to continue';
    }
    if (queue.failedJobCount > 0) {
      return zh ? '队列已处理，有任务失败' : 'Queue handled with failed jobs';
    }
    if (queue.cancelledJobCount > 0 && queue.succeededJobCount == 0) {
      return zh ? '任务已取消' : 'Jobs cancelled';
    }
    return zh ? '队列已处理完成' : 'Queue handled';
  }

  String _localizedRetryLabel(
    BuildContext context,
    int retryCount,
    int maxRetries,
  ) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '重试 $retryCount/$maxRetries'
        : 'retry $retryCount/$maxRetries';
  }

  String _localizedRetryActionLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '继续索引'
        : 'Continue indexing';
  }

  String _localizedIncompleteIndexText(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '未完成，可继续'
        : 'Incomplete, can continue';
  }

  String _localizedFailedIndexText(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '索引中断，可继续'
        : 'Index failed, can continue';
  }

  String _localizedChunkCountText(BuildContext context, int chunkCount) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? 'chunks: $chunkCount'
        : 'chunks: $chunkCount';
  }

  String? _chapterProgressText(BuildContext context, AiBookIndexInfo? info) {
    final total = info?.totalChapters ?? 0;
    if (total <= 0) return null;
    final done = (info?.doneChapters ?? 0).clamp(0, total);
    final percent = ((done / total) * 100).round();
    return Localizations.localeOf(context).languageCode == 'zh'
        ? '章节 $done/$total ($percent%)'
        : 'chapters $done/$total ($percent%)';
  }

  bool _canContinueIndex(AiBookIndexInfo? info) {
    if (info == null || info.chunkCount <= 0) return false;
    final status = (info.indexStatus ?? '').trim();
    if (status == 'failed' || status == 'running') return true;
    final total = info.totalChapters ?? 0;
    final done = info.doneChapters ?? 0;
    return total > 0 && done < total;
  }

  String? _indexContinuationText(BuildContext context, AiBookIndexInfo? info) {
    if (!_canContinueIndex(info)) return null;
    final status = (info?.indexStatus ?? '').trim();
    if (status == 'failed') return _localizedFailedIndexText(context);
    return _localizedIncompleteIndexText(context);
  }

  Future<AiBookIndexReadiness> _bookReadinessFuture(int bookId) {
    return _bookReadinessFutures.putIfAbsent(
      bookId,
      () {
        final loader = widget.bookReadinessLoader;
        if (loader != null) return loader(bookId);
        return AiBookIndexReadinessInspector().inspectBook(bookId);
      },
    );
  }

  Future<void> _repairBookBaseEmbeddings(
    int bookId,
    AiLibraryIndexQueueService? queueSvc,
  ) async {
    if (bookId <= 0 || _baseEmbeddingRepairBookIds.contains(bookId)) return;
    setState(() {
      _baseEmbeddingRepairBookIds.add(bookId);
      _bookLayerActionFailures.remove(bookId);
    });

    var succeeded = false;
    try {
      final repairer = widget.bookBaseEmbeddingRepairer;
      if (repairer != null) {
        await repairer(bookId);
      } else {
        await queueSvc?.enqueueBook(bookId);
      }
      succeeded = true;
      if (mounted) {
        final zh = _isZh(context);
        AnxToast.show(
          zh ? '已排队修复基础 embedding' : 'Base embedding repair queued',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final zh = _isZh(context);
      setState(() {
        _bookLayerActionFailures[bookId] = _BookIndexLayerActionFailure(
          action: _BookIndexLayerAction.baseEmbeddingRepair,
          message: e.toString(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '基础 embedding 修复失败：$e' : 'Base embedding repair failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _baseEmbeddingRepairBookIds.remove(bookId);
          if (succeeded) {
            _bookLayerActionFailures.remove(bookId);
          }
          _bookReadinessFutures.remove(bookId);
          _nativeVectorFuture = _loadNativeVectorStatus();
          _annVectorFuture = _loadAnnVectorStatus();
        });
        if (succeeded) {
          _scheduleBooksRefresh(const Duration(milliseconds: 500));
        }
      }
    }
  }

  Future<void> _buildBookGlobalLayer(int bookId) async {
    if (bookId <= 0 || _globalLayerBookBuildingIds.contains(bookId)) return;
    setState(() {
      _globalLayerBookBuildingIds.add(bookId);
      _bookLayerActionFailures.remove(bookId);
    });

    var succeeded = false;
    try {
      final builder = widget.bookGlobalLayerBuilder;
      if (builder != null) {
        await builder(bookId);
      } else {
        await AiGlobalIndexBuilder().rebuildBook(bookId: bookId);
      }
      succeeded = true;
    } catch (e) {
      if (!mounted) return;
      final zh = _isZh(context);
      setState(() {
        _bookLayerActionFailures[bookId] = _BookIndexLayerActionFailure(
          action: _BookIndexLayerAction.globalLayer,
          message: e.toString(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '全局层补建失败：$e' : 'Global layer build failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _globalLayerBookBuildingIds.remove(bookId);
          if (succeeded) {
            _bookLayerActionFailures.remove(bookId);
          }
          _bookReadinessFutures.remove(bookId);
          _globalLayerFuture = _loadMissingGlobalLayers();
        });
      }
    }
  }

  Future<void> _upgradeBookNativeVector(int bookId) async {
    if (bookId <= 0 || _nativeVectorBookBuildingIds.contains(bookId)) return;
    setState(() {
      _nativeVectorBookBuildingIds.add(bookId);
      _bookLayerActionFailures.remove(bookId);
    });

    var succeeded = false;
    try {
      final builder = widget.bookNativeVectorBuilder;
      if (builder != null) {
        await builder(bookId);
      } else {
        final db = await AiIndexDatabase.instance.database;
        await const AiNativeVectorIndexBuilder().backfillBook(
          db,
          bookId: bookId,
        );
      }
      succeeded = true;
    } catch (e) {
      if (!mounted) return;
      final zh = _isZh(context);
      setState(() {
        _bookLayerActionFailures[bookId] = _BookIndexLayerActionFailure(
          action: _BookIndexLayerAction.nativeVector,
          message: e.toString(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '向量层升级失败：$e' : 'Vector layer upgrade failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _nativeVectorBookBuildingIds.remove(bookId);
          if (succeeded) {
            _bookLayerActionFailures.remove(bookId);
          }
          _bookReadinessFutures.remove(bookId);
          _nativeVectorFuture = _loadNativeVectorStatus();
          _annVectorFuture = _loadAnnVectorStatus();
        });
      }
    }
  }

  Future<void> _buildBookAnnVector(int bookId) async {
    if (bookId <= 0 || _annVectorBookBuildingIds.contains(bookId)) return;
    setState(() {
      _annVectorBookBuildingIds.add(bookId);
      _bookLayerActionFailures.remove(bookId);
      _bookAnnVectorProgress.remove(bookId);
    });

    var succeeded = false;
    void recordProgress(AiVec1VectorIndexBuildProgress progress) {
      if (!mounted) return;
      setState(() {
        if (_annVectorBookBuildingIds.contains(bookId)) {
          _bookAnnVectorProgress[bookId] = progress;
        }
      });
    }

    try {
      final builder = widget.bookAnnVectorBuilder;
      if (builder != null) {
        await builder(bookId, onProgress: recordProgress);
        succeeded = true;
      } else {
        final db = await AiIndexDatabase.instance.database;
        final result = await const AiVec1VectorIndexBuilder()
            .rebuildBookSidecarFromNativeRows(
          db,
          bookId: bookId,
          onProgress: recordProgress,
        );
        if (!result.available && mounted) {
          final zh = _isZh(context);
          final message =
              result.lastError ?? 'Vec1/sqlite-vec extension was not detected';
          setState(() {
            _bookLayerActionFailures[bookId] = _BookIndexLayerActionFailure(
              action: _BookIndexLayerAction.annVector,
              message: message,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                zh
                    ? 'ANN sidecar 暂不可用：$message'
                    : 'ANN sidecar unavailable: $message',
              ),
            ),
          );
        } else {
          succeeded = true;
        }
      }
    } catch (e) {
      if (!mounted) return;
      final zh = _isZh(context);
      setState(() {
        _bookLayerActionFailures[bookId] = _BookIndexLayerActionFailure(
          action: _BookIndexLayerAction.annVector,
          message: e.toString(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? 'ANN sidecar 构建失败：$e' : 'ANN sidecar build failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _annVectorBookBuildingIds.remove(bookId);
          _bookAnnVectorProgress.remove(bookId);
          if (succeeded) {
            _bookLayerActionFailures.remove(bookId);
          }
          _bookReadinessFutures.remove(bookId);
          _annVectorFuture = _loadAnnVectorStatus();
        });
      }
    }
  }

  String _formatPercent(double value) {
    return AiLibraryIndexProgressText.formatPercent(value);
  }

  AiLibraryIndexJob? _latestQueueJobForBook(
    List<AiLibraryIndexJob> jobs,
    int bookId,
  ) {
    for (final job in jobs) {
      if (job.bookId == bookId) return job;
    }
    return null;
  }

  bool _isActiveBaseIndexJob(AiLibraryIndexJob? job) {
    return job?.status == AiLibraryIndexJobStatus.queued ||
        job?.status == AiLibraryIndexJobStatus.running ||
        job?.status == AiLibraryIndexJobStatus.paused;
  }

  bool _canRetryBaseIndexJob(AiLibraryIndexJob? job) {
    return job?.status == AiLibraryIndexJobStatus.failed ||
        job?.status == AiLibraryIndexJobStatus.cancelled;
  }

  bool _blocksDerivedLayerActions(AiLibraryIndexJob? job) {
    return _isActiveBaseIndexJob(job) || _canRetryBaseIndexJob(job);
  }

  String? _baseIndexJobText(
    BuildContext context,
    AiLibraryIndexJob? job,
  ) {
    if (!_blocksDerivedLayerActions(job)) return null;
    final languageCode = Localizations.localeOf(context).languageCode;
    final zh = languageCode == 'zh';
    final detail = AiLibraryIndexProgressText.detail(
      job: job!,
      languageCode: languageCode,
    );
    final parts = <String>[
      zh
          ? '基础索引任务：${_baseIndexJobStatusLabel(context, job.status)}'
          : 'Base index job: ${_baseIndexJobStatusLabel(context, job.status)}',
      _formatPercent(job.progress),
      if (detail.isNotEmpty) detail,
    ];

    final error = (job.lastError ?? '').trim();
    if (error.isNotEmpty) {
      parts.add(zh ? '错误：$error' : 'error: $error');
    }

    return parts.join(' · ');
  }

  String _baseIndexJobStatusLabel(
    BuildContext context,
    AiLibraryIndexJobStatus status,
  ) {
    final zh = _isZh(context);
    return switch (status) {
      AiLibraryIndexJobStatus.queued => zh ? '等待中' : 'queued',
      AiLibraryIndexJobStatus.running => zh ? '索引中' : 'running',
      AiLibraryIndexJobStatus.paused => zh ? '已暂停' : 'paused',
      AiLibraryIndexJobStatus.succeeded => zh ? '已完成' : 'done',
      AiLibraryIndexJobStatus.failed => zh ? '失败' : 'failed',
      AiLibraryIndexJobStatus.cancelled => zh ? '已取消' : 'cancelled',
    };
  }

  String? _baseIndexJobLayerBlockReason(
    BuildContext context,
    AiLibraryIndexJob? job,
  ) {
    if (!_blocksDerivedLayerActions(job)) return null;
    final zh = _isZh(context);
    return switch (job!.status) {
      AiLibraryIndexJobStatus.queued => zh
          ? '基础索引任务已排队。完成后再补建各层。'
          : 'Base index job is queued. Layer upgrades will be available after it finishes.',
      AiLibraryIndexJobStatus.running => zh
          ? '基础索引正在运行。完成后再补建各层。'
          : 'Base index job is running. Layer upgrades will be available after it finishes.',
      AiLibraryIndexJobStatus.paused => zh
          ? '基础索引已暂停。请先继续基础索引，再补建各层。'
          : 'Base index job is paused. Continue the base index before layer upgrades.',
      AiLibraryIndexJobStatus.failed => zh
          ? '基础索引任务失败。请先继续基础索引，再补建各层。'
          : 'Base index job failed. Continue the base index before layer upgrades.',
      AiLibraryIndexJobStatus.cancelled => zh
          ? '基础索引任务已取消。请先继续基础索引，再补建各层。'
          : 'Base index job was cancelled. Continue the base index before layer upgrades.',
      AiLibraryIndexJobStatus.succeeded => null,
    };
  }

  Widget _buildBookTile(
    BuildContext context,
    _BookRow r,
    AiLibraryIndexQueueState queue,
    AiLibraryIndexQueueService? queueSvc,
  ) {
    final book = r.result.book;
    final selected = _selectedBookIds.contains(book.id);
    final baseQueueJob = _latestQueueJobForBook(queue.jobs, book.id);

    IconData statusIcon = Icons.book_outlined;
    Color? statusColor;
    final canContinue = _canContinueIndex(r.indexInfo);
    final canRetryBaseQueueJob = _canRetryBaseIndexJob(baseQueueJob);
    final canShowRetryAction = canRetryBaseQueueJob ||
        (canContinue && !_isActiveBaseIndexJob(baseQueueJob));

    switch (r.status) {
      case _BookIndexStatus.unindexed:
        statusIcon = Icons.radio_button_unchecked;
      case _BookIndexStatus.expired:
        statusIcon = Icons.error_outline;
        statusColor = Theme.of(context).colorScheme.tertiary;
      case _BookIndexStatus.indexed:
        statusIcon = canContinue
            ? Icons.warning_amber_outlined
            : Icons.check_circle_outline;
        statusColor = canContinue
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.primary;
    }

    final chunkCount = r.indexInfo?.chunkCount ?? 0;
    final chapterProgress = _chapterProgressText(context, r.indexInfo);
    final continuationText = _indexContinuationText(context, r.indexInfo);

    final summaryParts = [
      book.author,
      if (!_selecting && chapterProgress != null) chapterProgress,
      if (!_selecting && chunkCount > 0)
        _localizedChunkCountText(context, chunkCount),
      if (!_selecting && continuationText != null) continuationText,
    ].where((e) => e.trim().isNotEmpty).toList(growable: false);

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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summaryParts.isNotEmpty)
            Text(
              summaryParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (!_selecting)
            _BookIndexLayerReadinessSummary(
              readinessFuture: _bookReadinessFuture(book.id),
              actionFailure: _bookLayerActionFailures[book.id],
              annVectorProgress: _bookAnnVectorProgress[book.id],
              baseQueueJobText: _baseIndexJobText(context, baseQueueJob),
              layerActionBlockReason:
                  _bookIndexLayerActionBlockReason(context, r, baseQueueJob),
              baseEmbeddingRepairing:
                  _baseEmbeddingRepairBookIds.contains(book.id),
              nativeVectorBuilding:
                  _nativeVectorBookBuildingIds.contains(book.id),
              annVectorBuilding: _annVectorBookBuildingIds.contains(book.id),
              globalLayerBuilding:
                  _globalLayerBookBuildingIds.contains(book.id),
              onRepairBaseEmbeddings: () =>
                  unawaited(_repairBookBaseEmbeddings(book.id, queueSvc)),
              onUpgradeNativeVector: () =>
                  unawaited(_upgradeBookNativeVector(book.id)),
              onBuildAnnVector: () => unawaited(_buildBookAnnVector(book.id)),
              onBuildGlobalLayer: () =>
                  unawaited(_buildBookGlobalLayer(book.id)),
            ),
        ],
      ),
      isThreeLine: !_selecting,
      trailing: !_selecting && canShowRetryAction
          ? IconButton(
              tooltip: _localizedRetryActionLabel(context),
              icon: const Icon(Icons.replay_outlined),
              onPressed: queueSvc == null
                  ? null
                  : () async {
                      AnxToast.show(_localizedRetryActionLabel(context));
                      await queueSvc.enqueueBook(book.id);
                      _scheduleBooksRefresh(const Duration(milliseconds: 500));
                    },
            )
          : null,
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

  String? _bookIndexLayerActionBlockReason(
    BuildContext context,
    _BookRow row,
    AiLibraryIndexJob? baseQueueJob,
  ) {
    final queueBlock = _baseIndexJobLayerBlockReason(context, baseQueueJob);
    if (queueBlock != null) return queueBlock;
    if (row.status != _BookIndexStatus.expired) return null;
    return _isZh(context)
        ? '当前设置下索引已过期。请先重建基础索引，再补建各层。'
        : 'Index is out of date for current settings. Rebuild the base index before layer upgrades.';
  }

  Future<List<_BookRow>> _loadBooks({
    required _Filter filter,
    required int token,
  }) async {
    final results = await (widget.bookSearchLoader ??
        ({required int limit}) => const BooksRepository().searchBooks(
              limit: limit,
            ))(limit: _bookListLimit);
    final ids = results.map((e) => e.book.id).toList(growable: false);
    final idx = await (widget.bookIndexInfoLoader ??
        (List<int> bookIds) => AiIndexDatabase.instance.getBookIndexInfos(
              bookIds,
            ))(ids);

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

class _BookIndexLayerReadinessSummary extends StatelessWidget {
  const _BookIndexLayerReadinessSummary({
    required this.readinessFuture,
    required this.actionFailure,
    required this.annVectorProgress,
    required this.baseQueueJobText,
    required this.layerActionBlockReason,
    required this.baseEmbeddingRepairing,
    required this.nativeVectorBuilding,
    required this.annVectorBuilding,
    required this.globalLayerBuilding,
    required this.onRepairBaseEmbeddings,
    required this.onUpgradeNativeVector,
    required this.onBuildAnnVector,
    required this.onBuildGlobalLayer,
  });

  final Future<AiBookIndexReadiness> readinessFuture;
  final _BookIndexLayerActionFailure? actionFailure;
  final AiVec1VectorIndexBuildProgress? annVectorProgress;
  final String? baseQueueJobText;
  final String? layerActionBlockReason;
  final bool baseEmbeddingRepairing;
  final bool nativeVectorBuilding;
  final bool annVectorBuilding;
  final bool globalLayerBuilding;
  final VoidCallback onRepairBaseEmbeddings;
  final VoidCallback onUpgradeNativeVector;
  final VoidCallback onBuildAnnVector;
  final VoidCallback onBuildGlobalLayer;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<AiBookIndexReadiness>(
      future: readinessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              zh ? '索引层状态：检查中...' : 'Index layers: checking...',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        final readiness = snapshot.data;
        if (readiness == null || snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              zh ? '索引层状态：无法读取' : 'Index layers unavailable',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        final reason = _firstReadinessReason(readiness);
        final availableText = _bookIndexAvailableCapabilitiesText(
          context,
          readiness,
        );
        final nextUnlockText = _bookIndexNextUnlockText(
          context,
          readiness,
        );
        final blockReason = layerActionBlockReason?.trim();
        final queueJobText = baseQueueJobText?.trim();
        final layerActionsBlocked =
            blockReason != null && blockReason.isNotEmpty;
        final hasQueueJobText = queueJobText != null && queueJobText.isNotEmpty;
        final failureText = _bookIndexLayerActionFailureText(
          context,
          actionFailure,
        );
        final progressText = _bookIndexLayerActionProgressText(
          context,
          annVectorProgress,
        );
        final nativeVectorRetry =
            actionFailure?.action == _BookIndexLayerAction.nativeVector;
        final baseEmbeddingRepairRetry =
            actionFailure?.action == _BookIndexLayerAction.baseEmbeddingRepair;
        final annVectorRetry =
            actionFailure?.action == _BookIndexLayerAction.annVector;
        final globalLayerRetry =
            actionFailure?.action == _BookIndexLayerAction.globalLayer;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    zh ? '索引层状态' : 'Index layers',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _BookIndexLayerChip(
                    label: zh ? '基础' : 'Base',
                    state: readiness.baseIndex.state,
                  ),
                  _BookIndexLayerChip(
                    label: zh ? '向量' : 'Vector',
                    state: readiness.nativeVector.state,
                  ),
                  _BookIndexLayerChip(
                    label: 'ANN',
                    state: readiness.annVector.state,
                  ),
                  _BookIndexLayerChip(
                    label: zh ? '全局' : 'Global',
                    state: readiness.globalLayer.state,
                  ),
                  _BookIndexLayerChip(
                    label: zh ? '图谱' : 'Graph',
                    state: readiness.graphLayer.state,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                availableText,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                nextUnlockText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasQueueJobText) ...[
                const SizedBox(height: 3),
                Text(
                  queueJobText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (layerActionsBlocked) ...[
                const SizedBox(height: 3),
                Text(
                  blockReason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (reason != null) ...[
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (failureText != null) ...[
                const SizedBox(height: 3),
                Text(
                  failureText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (progressText != null) ...[
                const SizedBox(height: 3),
                Text(
                  progressText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!layerActionsBlocked &&
                  readiness.canRepairBaseEmbeddings) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed:
                      baseEmbeddingRepairing ? null : onRepairBaseEmbeddings,
                  icon: Icon(
                    baseEmbeddingRepairing
                        ? Icons.hourglass_empty
                        : Icons.build_circle_outlined,
                    size: 16,
                  ),
                  label: Text(
                    baseEmbeddingRepairing
                        ? (zh
                            ? '正在修复基础 embedding...'
                            : 'Repairing base embeddings...')
                        : baseEmbeddingRepairRetry
                            ? (zh ? '重试基础 embedding' : 'Retry base embeddings')
                            : (zh
                                ? '修复基础 embedding'
                                : 'Repair base embeddings'),
                  ),
                  style: _inlineActionStyle(),
                ),
              ],
              if (!layerActionsBlocked && readiness.canUpgradeNativeVector) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed:
                      nativeVectorBuilding ? null : onUpgradeNativeVector,
                  icon: Icon(
                    nativeVectorBuilding
                        ? Icons.hourglass_empty
                        : Icons.view_in_ar_outlined,
                    size: 16,
                  ),
                  label: Text(
                    nativeVectorBuilding
                        ? (zh ? '正在升级向量层...' : 'Upgrading vector layer...')
                        : nativeVectorRetry
                            ? (zh ? '重试向量层' : 'Retry vector layer')
                            : (zh ? '升级向量层' : 'Upgrade vector layer'),
                  ),
                  style: _inlineActionStyle(),
                ),
              ],
              if (!layerActionsBlocked && readiness.canBuildAnnVector) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: annVectorBuilding ? null : onBuildAnnVector,
                  icon: Icon(
                    annVectorBuilding
                        ? Icons.hourglass_empty
                        : Icons.hub_outlined,
                    size: 16,
                  ),
                  label: Text(
                    annVectorBuilding
                        ? (zh
                            ? '正在构建 ANN sidecar...'
                            : 'Building ANN sidecar...')
                        : annVectorRetry
                            ? (zh ? '重试 ANN sidecar' : 'Retry ANN sidecar')
                            : (zh ? '构建 ANN sidecar' : 'Build ANN sidecar'),
                  ),
                  style: _inlineActionStyle(),
                ),
              ],
              if (!layerActionsBlocked && readiness.canBuildGlobalLayer) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: globalLayerBuilding ? null : onBuildGlobalLayer,
                  icon: Icon(
                    globalLayerBuilding
                        ? Icons.hourglass_empty
                        : Icons.auto_graph_outlined,
                    size: 16,
                  ),
                  label: Text(
                    globalLayerBuilding
                        ? (zh ? '正在补建全局层...' : 'Building global layer...')
                        : globalLayerRetry
                            ? (zh ? '重试全局层' : 'Retry global layer')
                            : (zh ? '补建全局层' : 'Build global layer'),
                  ),
                  style: _inlineActionStyle(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  ButtonStyle _inlineActionStyle() {
    return TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BookIndexLayerChip extends StatelessWidget {
  const _BookIndexLayerChip({
    required this.label,
    required this.state,
  });

  final String label;
  final AiBookIndexLayerState state;

  @override
  Widget build(BuildContext context) {
    final text = '$label ${_bookLayerStateLabel(context, state)}';
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      AiBookIndexLayerState.ready => scheme.primary,
      AiBookIndexLayerState.running => scheme.tertiary,
      AiBookIndexLayerState.failed => scheme.error,
      AiBookIndexLayerState.unavailable => scheme.outline,
      AiBookIndexLayerState.empty => scheme.outline,
      AiBookIndexLayerState.missing => scheme.outline,
    };
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _bookLayerStateLabel(
  BuildContext context,
  AiBookIndexLayerState state,
) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (state) {
    AiBookIndexLayerState.ready => zh ? '已就绪' : 'Ready',
    AiBookIndexLayerState.missing => zh ? '缺失' : 'Missing',
    AiBookIndexLayerState.running => zh ? '进行中' : 'Running',
    AiBookIndexLayerState.failed => zh ? '失败' : 'Failed',
    AiBookIndexLayerState.unavailable => zh ? '暂不可用' : 'Unavailable',
    AiBookIndexLayerState.empty => zh ? '暂无节点' : 'Empty',
  };
}

String? _firstReadinessReason(AiBookIndexReadiness readiness) {
  final layers = [
    readiness.baseIndex,
    readiness.nativeVector,
    readiness.annVector,
    readiness.globalLayer,
    readiness.graphLayer,
  ];
  for (final layer in layers) {
    final reason = layer.reason?.trim();
    if (reason != null && reason.isNotEmpty) return reason;
  }
  return null;
}

String _bookIndexAvailableCapabilitiesText(
  BuildContext context,
  AiBookIndexReadiness readiness,
) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final baseReady = readiness.baseIndex.state == AiBookIndexLayerState.ready;
  final nativeReady =
      readiness.nativeVector.state == AiBookIndexLayerState.ready;
  final annReady = readiness.annVector.state == AiBookIndexLayerState.ready;
  final globalReady =
      readiness.globalLayer.state == AiBookIndexLayerState.ready;
  final graphReady = readiness.graphLayer.state == AiBookIndexLayerState.ready;

  if (!baseReady) {
    return zh
        ? '现在可用：暂未具备 AI 阅读能力。'
        : 'Available now: no AI reading features yet.';
  }

  final parts = <String>[
    zh ? '当前书问答' : 'current-book Q&A',
    zh ? '原文跳转' : 'source jumps',
    if (nativeReady || annReady) zh ? '语义搜索' : 'semantic search',
    if (annReady) zh ? '大书快速召回' : 'fast large-book recall',
    if (globalReady) zh ? '全书摘要层' : 'book-level summaries',
    if (graphReady) zh ? '本书地图' : 'book map',
  ];

  return zh
      ? '现在可用：${parts.join('、')}。'
      : 'Available now: ${parts.join(', ')}.';
}

String _bookIndexNextUnlockText(
  BuildContext context,
  AiBookIndexReadiness readiness,
) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final baseReady = readiness.baseIndex.state == AiBookIndexLayerState.ready;
  final nativeReady =
      readiness.nativeVector.state == AiBookIndexLayerState.ready;
  final annReady = readiness.annVector.state == AiBookIndexLayerState.ready;
  final globalReady =
      readiness.globalLayer.state == AiBookIndexLayerState.ready;
  final graphReady = readiness.graphLayer.state == AiBookIndexLayerState.ready;

  if (!baseReady) {
    return zh
        ? '下一步解锁：先完成基础索引，启用 AI 问答和证据跳转。'
        : 'Next unlock: build the base index to enable AI Q&A and evidence jumps.';
  }

  final parts = <String>[];
  if (!nativeReady) {
    parts.add(
      zh
          ? '升级向量层以降低语义搜索内存占用'
          : 'upgrade vector layer for lighter semantic search',
    );
  }
  if (nativeReady && !annReady) {
    parts.add(
      zh ? '构建 ANN 加速大书搜索' : 'build ANN for faster large-book search',
    );
  }
  if (!globalReady) {
    parts.add(
      zh
          ? '补建全局层生成本书地图和导读路径'
          : 'build global layer for book map and reading path',
    );
  } else if (!graphReady) {
    parts.add(
      zh ? '生成图谱层以显示概念关系' : 'build graph layer for concept links',
    );
  }

  if (parts.isEmpty) {
    return zh
        ? '下一步解锁：书籍理解层已就绪，可直接在 AI Chat 或图谱页使用。'
        : 'Next unlock: book understanding stack is ready for AI Chat and the graph page.';
  }

  return zh ? '下一步解锁：${parts.join('；')}。' : 'Next unlock: ${parts.join('; ')}.';
}

String? _bookIndexLayerActionFailureText(
  BuildContext context,
  _BookIndexLayerActionFailure? failure,
) {
  if (failure == null) return null;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final message = failure.message.trim();
  final suffix = message.isEmpty ? '' : ': $message';
  return switch (failure.action) {
    _BookIndexLayerAction.baseEmbeddingRepair =>
      zh ? '基础 embedding 修复失败$suffix' : 'Base embedding repair failed$suffix',
    _BookIndexLayerAction.globalLayer =>
      zh ? '全局层补建失败$suffix' : 'Global layer build failed$suffix',
    _BookIndexLayerAction.nativeVector =>
      zh ? '向量层升级失败$suffix' : 'Vector layer upgrade failed$suffix',
    _BookIndexLayerAction.annVector =>
      zh ? 'ANN sidecar 构建失败$suffix' : 'ANN sidecar build failed$suffix',
  };
}

String? _bookIndexLayerActionProgressText(
  BuildContext context,
  AiVec1VectorIndexBuildProgress? progress,
) {
  if (progress == null) return null;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return zh
      ? 'ANN sidecar 进度：${progress.done}/${progress.total} 组，已写 ${progress.rowsWritten} 行。'
      : 'ANN sidecar progress: ${progress.done}/${progress.total} group(s), ${progress.rowsWritten} row(s) written.';
}
