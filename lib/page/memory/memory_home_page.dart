import 'dart:io';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/memory/memory_bulk_selection_controller.dart';
import 'package:papertok_reader/page/memory/memory_detail_page.dart';
import 'package:papertok_reader/page/memory/widgets/memory_row.dart';
import 'package:papertok_reader/page/memory/widgets/tag_editor.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_pending_count_provider.dart';
import 'package:papertok_reader/service/memory/memory_source_ref_adapter.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryHomePage extends ConsumerStatefulWidget {
  final MarkdownMemoryStore? store;

  const MemoryHomePage({super.key, this.store});

  @override
  ConsumerState<MemoryHomePage> createState() => _MemoryHomePageState();
}

class _MemoryHomePageState extends ConsumerState<MemoryHomePage> {
  final _bulk = MemoryBulkSelectionController();

  @override
  void initState() {
    super.initState();
    _bulk.addListener(_onBulkChange);
  }

  @override
  void dispose() {
    _bulk.removeListener(_onBulkChange);
    _bulk.dispose();
    super.dispose();
  }

  void _onBulkChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete() async {
    final count = _bulk.selectionCount;
    final l10n = L10n.of(context);
    final confirmed = await PTDialog.show<bool>(
      context,
      title: l10n.memoryBulkDeleteConfirmTitle,
      message: l10n.memoryBulkDeleteConfirmBody(count),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PTDialogAction(
          label: l10n.memoryBulkDeleteAction,
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (confirmed != true) return;

    for (final path in _bulk.selected.toList()) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort; surface a toast on failure.
        }
      }
    }
    _bulk.clear();
    if (mounted) setState(() {});
  }

  Future<void> _showAddTagSheet() async {
    final store = widget.store ?? MarkdownMemoryStore();
    final selection = _bulk.selected.toList();
    final l10n = L10n.of(context);

    await PTBottomSheet.show<void>(
      context,
      title: l10n.memoryBulkAddTagTitle,
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TagEditor(
            initial: const <String>[],
            suggestions: const <String>[],
            onChanged: (tags) async {
              if (tags.isEmpty) return;
              for (final path in selection) {
                final existing = await store.readEntryTags(path);
                final merged = <String>{...existing, ...tags}.toList();
                await store.writeEntryTags(path, merged);
              }
            },
          ),
        );
      },
    );
    _bulk.clear();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(memoryPendingCountProvider).valueOrNull ?? 0;
    final l10n = L10n.of(context);
    final effectiveStore = widget.store ?? MarkdownMemoryStore();

    return Scaffold(
      appBar: AppBar(
        leading: _bulk.inSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _bulk.clear,
              )
            : null,
        title: Text(
          _bulk.inSelectionMode
              ? l10n.memoryBulkSelectionCount(_bulk.selectionCount)
              : l10n.memoryTabTitle,
        ),
        actions: _bulk.inSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.memoryBulkDeleteTooltip,
                  onPressed: _bulk.selectionCount == 0 ? null : _confirmDelete,
                ),
                IconButton(
                  icon: const Icon(Icons.label_outline),
                  tooltip: l10n.memoryBulkAddTagTooltip,
                  onPressed:
                      _bulk.selectionCount == 0 ? null : _showAddTagSheet,
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _SectionHeader(title: l10n.memoryInboxSectionTitle),
          _InboxSummaryCard(pendingCount: pendingCount),
          _SectionHeader(title: l10n.memoryTodaySectionTitle),
          _MemoryEntriesCard(
            future: effectiveStore.listRecentDailyNotes(count: 14),
            emptyMessage: l10n.memoryHomeTodayEmpty,
            store: effectiveStore,
            bulk: _bulk,
          ),
          _SectionHeader(title: l10n.memoryLongTermSectionTitle),
          _MemoryEntriesCard(
            future: effectiveStore.listLongTermEntries(),
            emptyMessage: l10n.memoryHomeLongTermEmpty,
            store: effectiveStore,
            bulk: _bulk,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: ClaudePalette.secondary(context),
        ),
      ),
    );
  }
}

class _MemoryEntriesCard extends StatelessWidget {
  final Future<List<MemoryEntryRef>> future;
  final String emptyMessage;
  final MarkdownMemoryStore store;
  final MemoryBulkSelectionController bulk;

  const _MemoryEntriesCard({
    required this.future,
    required this.emptyMessage,
    required this.store,
    required this.bulk,
  });

  Future<_MemoryEntriesSnapshot> _loadEntries() async {
    final entries = await future;
    if (entries.isEmpty) {
      return const _MemoryEntriesSnapshot(
        entries: <MemoryEntryRef>[],
        sourceRefsByIndex: <int, List<SourceRef>>{},
      );
    }

    final candidates = await MemoryCandidateStore(
      rootDir: store.rootDir,
    ).list(status: MemoryCandidateStatus.applied);
    if (candidates.isEmpty) {
      return _MemoryEntriesSnapshot(
        entries: entries,
        sourceRefsByIndex: const <int, List<SourceRef>>{},
      );
    }

    final sourceRefsByIndex = <int, List<SourceRef>>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final body = await _readEntryBody(entry);
      final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
        entry: entry,
        body: body,
        candidates: candidates,
      );
      if (sourceRefs.isNotEmpty) {
        sourceRefsByIndex[i] = sourceRefs;
      }
    }

    return _MemoryEntriesSnapshot(
      entries: entries,
      sourceRefsByIndex: sourceRefsByIndex,
    );
  }

  Future<String> _readEntryBody(MemoryEntryRef entry) async {
    if (entry.body.trim().isNotEmpty) return entry.body;
    final file = File(entry.path);
    if (!file.existsSync()) return '';
    try {
      return file.readAsString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MemoryEntriesSnapshot>(
      future: _loadEntries(),
      builder: (context, snapshot) {
        final state = snapshot.data;
        final entries = state?.entries ?? const <MemoryEntryRef>[];
        final loading = snapshot.connectionState != ConnectionState.done;

        if (loading) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ClaudePalette.tertiary(context),
                ),
              ),
            ),
          );
        }

        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 13,
                color: ClaudePalette.tertiary(context),
              ),
            ),
          );
        }

        return Material(
          color: ClaudePalette.card(context),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                MemoryRow(
                  entry: entries[i],
                  sourceRefs:
                      state?.sourceRefsByIndex[i] ?? const <SourceRef>[],
                  selectionMode:
                      bulk.inSelectionMode && entries[i].supportsBulkActions,
                  selected: entries[i].supportsBulkActions &&
                      bulk.selected.contains(entries[i].path),
                  onTap: () async {
                    if (bulk.inSelectionMode) {
                      if (entries[i].supportsBulkActions) {
                        bulk.toggle(entries[i].path);
                      }
                      return;
                    }
                    final allKnownTags = <String>{};
                    for (final e in entries) {
                      allKnownTags.addAll(await store.readEntryTags(e.path));
                    }
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MemoryDetailPage(
                          entry: entries[i],
                          store: store,
                          allKnownTags: allKnownTags.toList(),
                        ),
                      ),
                    );
                  },
                  onLongPress: entries[i].supportsBulkActions
                      ? () {
                          HapticFeedback.mediumImpact();
                          bulk.enter(seedId: entries[i].path);
                        }
                      : null,
                ),
                if (i < entries.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: ClaudePalette.divider(context),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MemoryEntriesSnapshot {
  final List<MemoryEntryRef> entries;
  final Map<int, List<SourceRef>> sourceRefsByIndex;

  const _MemoryEntriesSnapshot({
    required this.entries,
    required this.sourceRefsByIndex,
  });
}

class _InboxSummaryCard extends StatelessWidget {
  final int pendingCount;
  const _InboxSummaryCard({required this.pendingCount});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Material(
      color: ClaudePalette.card(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Task 8 will wire this to the inbox detail / settings memory page.
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.inbox_outlined, color: ClaudePalette.fg(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.memoryInboxSectionTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ClaudePalette.fg(context),
                  ),
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ClaudePalette.accent(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pendingCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right,
                    color: ClaudePalette.tertiary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
