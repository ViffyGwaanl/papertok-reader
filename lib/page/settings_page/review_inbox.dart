import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/service/deeplink/paperreader_deeplink_handler.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_evidence_list.dart';

class ReviewInboxPage extends ConsumerStatefulWidget {
  const ReviewInboxPage({super.key});

  @override
  ConsumerState<ReviewInboxPage> createState() => _ReviewInboxPageState();
}

class _ReviewInboxPageState extends ConsumerState<ReviewInboxPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reviewInboxProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = ref.watch(reviewInboxProvider);

    return SettingsSubpageScaffold(
      title: l10n.reviewInboxTitle,
      actions: [
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(reviewInboxProvider.notifier).refresh(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewInboxHeader(state: state),
          Expanded(
            child: state.items.when(
              data: (items) => _ReviewInboxList(items: items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ReviewInboxError(error: error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewInboxHeader extends ConsumerWidget {
  const _ReviewInboxHeader({required this.state});

  final ReviewInboxState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reviewInboxDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final status in ReviewItemStatus.values) ...[
                  ChoiceChip(
                    label: Text(_statusLabel(l10n, status)),
                    selected: state.statusFilter == status,
                    onSelected: (_) => ref
                        .read(reviewInboxProvider.notifier)
                        .setStatusFilter(status),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<ReviewItemSourceType?>(
            value: state.sourceTypeFilter,
            isExpanded: true,
            items: [
              DropdownMenuItem<ReviewItemSourceType?>(
                value: null,
                child: Text(l10n.reviewInboxSourceAll),
              ),
              for (final type in ReviewItemSourceType.values)
                DropdownMenuItem<ReviewItemSourceType?>(
                  value: type,
                  child: Text(_sourceTypeLabel(l10n, type)),
                ),
            ],
            onChanged: (value) => ref
                .read(reviewInboxProvider.notifier)
                .setSourceTypeFilter(value),
          ),
        ],
      ),
    );
  }
}

class _ReviewInboxList extends ConsumerWidget {
  const _ReviewInboxList({required this.items});

  final List<ReviewItem> items;

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
              const Icon(Icons.fact_check_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                l10n.memoryReviewInboxEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.reviewInboxEmptyBody,
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
      onRefresh: () => ref.read(reviewInboxProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _ReviewInboxCard(item: items[index]),
      ),
    );
  }
}

class _ReviewInboxCard extends ConsumerWidget {
  const _ReviewInboxCard({required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final state = ref.watch(reviewInboxProvider);
    final busy = state.isBusy(item.id);
    final audit = ref.read(reviewInboxControllerProvider).sourceJumpAudit(item);
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
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _TinyChip(label: _statusLabel(l10n, item.status)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TinyChip(label: _sourceTypeLabel(l10n, item.sourceType)),
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
              item.body,
              maxLines: 4,
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
                      ? null
                      : () => PaperReaderDeepLinkHandler.handleIncomingUri(
                            ref,
                            firstIntent.toUri(),
                          ),
                ),
                if (item.status == ReviewItemStatus.pending) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.close),
                    label: Text(l10n.reviewInboxDismissAction),
                    onPressed: busy
                        ? null
                        : () => ref
                            .read(reviewInboxProvider.notifier)
                            .dismiss(item.id),
                  ),
                  FilledButton.icon(
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(l10n.reviewInboxApproveAction),
                    onPressed: busy
                        ? null
                        : () => ref
                            .read(reviewInboxProvider.notifier)
                            .approve(item.id),
                  ),
                ],
                if (item.status == ReviewItemStatus.approved)
                  FilledButton.icon(
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all),
                    label: Text(l10n.reviewInboxApplyAction),
                    onPressed: busy ||
                            !item.canApply ||
                            (item.sourceType !=
                                    ReviewItemSourceType.knowledgeCard &&
                                item.sourceType !=
                                    ReviewItemSourceType.conceptGraphRelation)
                        ? null
                        : () => ref
                            .read(reviewInboxProvider.notifier)
                            .apply(item.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewInboxError extends ConsumerWidget {
  const _ReviewInboxError({required this.error});

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
              onPressed: () => ref.read(reviewInboxProvider.notifier).refresh(),
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

String _statusLabel(L10n l10n, ReviewItemStatus status) {
  return switch (status) {
    ReviewItemStatus.draft => l10n.reviewInboxStatusDraft,
    ReviewItemStatus.pending => l10n.reviewInboxStatusPending,
    ReviewItemStatus.approved => l10n.reviewInboxStatusApproved,
    ReviewItemStatus.dismissed => l10n.reviewInboxStatusDismissed,
    ReviewItemStatus.applied => l10n.reviewInboxStatusApplied,
  };
}

String _sourceTypeLabel(L10n l10n, ReviewItemSourceType type) {
  return switch (type) {
    ReviewItemSourceType.memoryCandidate =>
      l10n.reviewInboxSourceMemoryCandidate,
    ReviewItemSourceType.knowledgeCard => l10n.reviewInboxSourceKnowledgeCard,
    ReviewItemSourceType.seminarSynthesis =>
      l10n.reviewInboxSourceSeminarSynthesis,
    ReviewItemSourceType.conceptGraphRelation =>
      l10n.reviewInboxSourceConceptGraphRelation,
    ReviewItemSourceType.flashcardCandidate =>
      l10n.reviewInboxSourceFlashcardCandidate,
    ReviewItemSourceType.imageAnalysisCard =>
      l10n.reviewInboxSourceImageAnalysisCard,
    ReviewItemSourceType.unknown => l10n.reviewInboxSourceUnknown,
  };
}
