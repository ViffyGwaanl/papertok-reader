import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/memory/memory_pending_count_provider.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryHomePage extends ConsumerWidget {
  const MemoryHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount =
        ref.watch(memoryPendingCountProvider).valueOrNull ?? 0;
    final l10n = L10n.of(context);

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
          const SizedBox(height: 4),
          // Task 8 will replace this with a card wrapping MemoryRow list.
          _SectionHeader(title: l10n.memoryLongTermSectionTitle),
          const SizedBox(height: 4),
          // Task 8 will replace this with a card wrapping MemoryRow list.
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
