import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_evidence_list.dart';

class SpacedReviewPage extends ConsumerStatefulWidget {
  const SpacedReviewPage({
    super.key,
    this.sourceOpener,
  });

  final PaperReaderSourceOpener? sourceOpener;

  @override
  ConsumerState<SpacedReviewPage> createState() => _SpacedReviewPageState();
}

class _SpacedReviewPageState extends ConsumerState<SpacedReviewPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(spacedReviewProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = ref.watch(spacedReviewProvider);

    return SettingsSubpageScaffold(
      title: l10n.spacedReviewTitle,
      actions: [
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(spacedReviewProvider.notifier).refresh(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SpacedReviewHeader(state: state),
          Expanded(
            child: state.items.when(
              data: (items) => _SpacedReviewList(
                items: items,
                sourceOpener: widget.sourceOpener ?? openPaperReaderSource,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _SpacedReviewError(error: error),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpacedReviewHeader extends ConsumerWidget {
  const _SpacedReviewHeader({required this.state});

  final SpacedReviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.spacedReviewDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.spacedReviewDueOnly),
                selected: state.dueOnly,
                onSelected: (_) =>
                    ref.read(spacedReviewProvider.notifier).setDueOnly(true),
              ),
              ChoiceChip(
                label: Text(l10n.spacedReviewAllItems),
                selected: !state.dueOnly,
                onSelected: (_) =>
                    ref.read(spacedReviewProvider.notifier).setDueOnly(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpacedReviewList extends ConsumerWidget {
  const _SpacedReviewList({
    required this.items,
    required this.sourceOpener,
  });

  final List<SpacedReviewItem> items;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                l10n.spacedReviewEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.spacedReviewEmptyBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(spacedReviewProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _SpacedReviewCard(
          item: items[index],
          sourceOpener: sourceOpener,
        ),
      ),
    );
  }
}

class _SpacedReviewCard extends ConsumerWidget {
  const _SpacedReviewCard({
    required this.item,
    required this.sourceOpener,
  });

  final SpacedReviewItem item;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final state = ref.watch(spacedReviewProvider);
    final busy = state.isBusy(item.id);
    final audit = ref.read(spacedReviewStoreProvider).sourceJumpAudit(item);
    final isDue = item.isDue(DateTime.now().millisecondsSinceEpoch);
    final firstIntent = item.sourceRefs
        .map(PaperReaderReaderIntent.fromSourceRef)
        .whereType<PaperReaderReaderIntent>()
        .firstOrNull;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: ClaudePalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.school_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.prompt,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TinyChip(
                  label: isDue
                      ? l10n.spacedReviewDueNow
                      : l10n.spacedReviewScheduled,
                ),
                if (item.intervalDays > 0)
                  _TinyChip(
                    label: l10n.spacedReviewIntervalDays(item.intervalDays),
                  ),
                if (item.reviewHistory.isNotEmpty)
                  _TinyChip(
                    label: l10n
                        .spacedReviewHistoryCount(item.reviewHistory.length),
                  ),
                if (audit.jumpableCount > 0)
                  _TinyChip(
                    label: l10n.reviewInboxTraceableSources(
                      audit.jumpableCount,
                    ),
                  ),
                if (audit.unavailableCount > 0)
                  _TinyChip(
                    label: l10n.reviewInboxUnavailableSources(
                      audit.unavailableCount,
                    ),
                  ),
                if (audit.unresolvedIndexes.isNotEmpty)
                  _TinyChip(
                    label: l10n.reviewInboxUnresolvedSources(
                      audit.unresolvedIndexes.length,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.answer,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.sourceRefs.any((ref) => ref.hasEvidence)) ...[
              const SizedBox(height: 10),
              SourceRefEvidenceList(sourceRefs: item.sourceRefs),
            ],
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.reviewInboxOpenSourceAction),
                  onPressed: firstIntent == null
                      ? () => showPaperReaderSourceUnavailable(
                            context,
                            item.sourceRefs,
                            l10n.conceptGraphNoEvidence,
                          )
                      : () => sourceOpener(
                            ref,
                            firstIntent.toUri(),
                          ),
                ),
                _RatingButton(
                  icon: Icons.replay,
                  label: l10n.spacedReviewAgain,
                  busy: busy,
                  onPressed: () => ref
                      .read(spacedReviewProvider.notifier)
                      .record(item.id, SpacedReviewRating.again),
                ),
                _RatingButton(
                  icon: Icons.trending_flat,
                  label: l10n.spacedReviewHard,
                  busy: busy,
                  onPressed: () => ref
                      .read(spacedReviewProvider.notifier)
                      .record(item.id, SpacedReviewRating.hard),
                ),
                _RatingButton(
                  icon: Icons.check,
                  label: l10n.spacedReviewGood,
                  busy: busy,
                  onPressed: () => ref
                      .read(spacedReviewProvider.notifier)
                      .record(item.id, SpacedReviewRating.good),
                ),
                _RatingButton(
                  icon: Icons.keyboard_double_arrow_up,
                  label: l10n.spacedReviewEasy,
                  busy: busy,
                  onPressed: () => ref
                      .read(spacedReviewProvider.notifier)
                      .record(item.id, SpacedReviewRating.easy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: busy ? null : onPressed,
    );
  }
}

class _SpacedReviewError extends ConsumerWidget {
  const _SpacedReviewError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reviewInboxActionFailed),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
              onPressed: () =>
                  ref.read(spacedReviewProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
