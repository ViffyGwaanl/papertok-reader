import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/memory/memory_detail_page.dart';
import 'package:anx_reader/page/memory/widgets/memory_row.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_pending_count_provider.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryHomePage extends ConsumerWidget {
  final MarkdownMemoryStore? store;

  const MemoryHomePage({super.key, this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount =
        ref.watch(memoryPendingCountProvider).valueOrNull ?? 0;
    final l10n = L10n.of(context);
    final effectiveStore = store ?? MarkdownMemoryStore();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.memoryTabTitle),
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
          ),
          _SectionHeader(title: l10n.memoryLongTermSectionTitle),
          _MemoryEntriesCard(
            future: effectiveStore.listLongTermEntries(),
            emptyMessage: l10n.memoryHomeLongTermEmpty,
            store: effectiveStore,
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

  const _MemoryEntriesCard({
    required this.future,
    required this.emptyMessage,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MemoryEntryRef>>(
      future: future,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <MemoryEntryRef>[];
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
                  onTap: () async {
                    final allKnownTags = <String>{};
                    for (final e in entries) {
                      allKnownTags
                          .addAll(await store.readEntryTags(e.path));
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
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
