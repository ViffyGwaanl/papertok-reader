import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/knowledge_asset_export.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/page_transitions.dart';

class KnowledgeAssetExportPage extends ConsumerStatefulWidget {
  const KnowledgeAssetExportPage({super.key});

  @override
  ConsumerState<KnowledgeAssetExportPage> createState() =>
      _KnowledgeAssetExportPageState();
}

class _KnowledgeAssetExportPageState
    extends ConsumerState<KnowledgeAssetExportPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(knowledgeAssetExportProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = ref.watch(knowledgeAssetExportProvider);

    return SettingsSubpageScaffold(
      title: l10n.knowledgeExportTitle,
      actions: [
        IconButton(
          tooltip: l10n.commonRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: () =>
              ref.read(knowledgeAssetExportProvider.notifier).refresh(),
        ),
      ],
      child: state.snapshot.when(
        data: (snapshot) => _KnowledgeAssetExportBody(
          snapshot: snapshot,
          state: state,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _KnowledgeAssetExportError(error: error),
      ),
    );
  }
}

class _KnowledgeAssetExportBody extends ConsumerWidget {
  const _KnowledgeAssetExportBody({
    required this.snapshot,
    required this.state,
  });

  final KnowledgeAssetExportSnapshot snapshot;
  final KnowledgeAssetExportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final hasAssets = snapshot.includedCount > 0 || snapshot.excludedCount > 0;
    if (!hasAssets) {
      return _KnowledgeAssetExportEmpty();
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(knowledgeAssetExportProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            l10n.knowledgeExportDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          if (state.lastError case final error?) ...[
            const SizedBox(height: 8),
            _PolicyNote(text: error),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyChip(
                label: l10n.knowledgeExportIncludedCount(
                  snapshot.includedCount,
                ),
              ),
              _TinyChip(
                label: l10n.knowledgeExportExcludedCount(
                  snapshot.excludedCount,
                ),
              ),
              _TinyChip(
                label: l10n.knowledgeExportConflictCount(
                  snapshot.conflictCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PolicyNote(text: l10n.knowledgeExportSafeDefault),
          const SizedBox(height: 8),
          _RemoteSyncStatusPanel(status: state.remoteSyncStatus),
          if (state.lastManifestPath case final path?) ...[
            const SizedBox(height: 12),
            _PolicyNote(text: l10n.knowledgeExportManifestPath(path)),
          ],
          if (state.lastMarkdownPath case final path?) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportMarkdownPath(path)),
          ],
          if (state.lastHtmlReportPath case final path?) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportHtmlReportPath(path)),
          ],
          if (state.lastAnkiPath case final path?) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportAnkiPath(path)),
          ],
          if (state.lastSyncBundlePath case final path?) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportSyncBundlePath(path)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: state.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.description_outlined),
            label: Text(l10n.knowledgeExportCreateBundle),
            onPressed: state.busy
                ? null
                : () => ref
                    .read(knowledgeAssetExportProvider.notifier)
                    .createManifest(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_sync_outlined),
            label: Text(l10n.knowledgeExportPreviewRemoteSync),
            onPressed: state.busy
                ? null
                : () => ref
                    .read(knowledgeAssetExportProvider.notifier)
                    .previewRemoteSync(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.sync_outlined),
            label: Text(l10n.knowledgeExportRunSafeRemoteSync),
            onPressed: state.busy
                ? null
                : () => ref
                    .read(knowledgeAssetExportProvider.notifier)
                    .runSafeRemoteSync(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(l10n.knowledgeExportUploadRemoteSync),
            onPressed: state.busy
                ? null
                : () => ref
                    .read(knowledgeAssetExportProvider.notifier)
                    .uploadRemoteSyncBundle(),
          ),
          if (state.remotePreview case final preview?) ...[
            const SizedBox(height: 8),
            _RemotePreviewSection(
              preview: preview,
              busy: state.busy,
            ),
          ],
          if (state.lastRemoteIncomingReviewCount case final count?) ...[
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteIncomingReviewSent(count),
            ),
            if (count > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l10n.reviewInboxTitle),
                onPressed: () => Navigator.of(context).push(
                  CupertinoStyleRoute(
                    page: const ReviewInboxPage(),
                  ),
                ),
              ),
            ],
          ],
          if (state.lastRemoteReviewHistoryReviewCount case final count?) ...[
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteReviewHistoryReviewSent(count),
            ),
            if (count > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l10n.reviewInboxTitle),
                onPressed: () => Navigator.of(context).push(
                  CupertinoStyleRoute(
                    page: const ReviewInboxPage(),
                  ),
                ),
              ),
            ],
          ],
          if (state.lastRemoteConflictStageCount case final count?) ...[
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteConflictStageSent(count),
            ),
            if (count > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l10n.reviewInboxTitle),
                onPressed: () => Navigator.of(context).push(
                  CupertinoStyleRoute(
                    page: const ReviewInboxPage(),
                  ),
                ),
              ),
            ],
          ],
          if (state.lastRemoteConflictReviewCount case final count?) ...[
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteConflictReviewSent(count),
            ),
            if (count > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l10n.reviewInboxTitle),
                onPressed: () => Navigator.of(context).push(
                  CupertinoStyleRoute(
                    page: const ReviewInboxPage(),
                  ),
                ),
              ),
            ],
          ],
          if (state.lastRemoteUploadPath case final path?) ...[
            const SizedBox(height: 8),
            _PolicyNote(text: l10n.knowledgeExportRemoteUploadPath(path)),
            if (state.lastRemoteUploadCount case final count?) ...[
              const SizedBox(height: 6),
              _TinyChip(label: l10n.knowledgeExportRemoteUploadCount(count)),
            ],
          ],
          if (state.lastRemoteRollbackPath case final path?) ...[
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteRollbackSnapshotPath(path),
            ),
          ],
          if (state.lastRemoteRollbackRestored == true) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportRemoteRollbackRestored),
          ],
          if (state.lastRemotePartialRemoved == true) ...[
            const SizedBox(height: 6),
            _PolicyNote(text: l10n.knowledgeExportRemotePartialRemoved),
          ],
          if (snapshot.conflictCount > 0) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.rate_review_outlined),
              label: Text(l10n.knowledgeExportSendConflictsToReview),
              onPressed: state.busy
                  ? null
                  : () => ref
                      .read(knowledgeAssetExportProvider.notifier)
                      .submitConflictsToReview(),
            ),
          ],
          if (state.lastConflictReviewCount case final count?) ...[
            const SizedBox(height: 8),
            _PolicyNote(text: l10n.knowledgeExportConflictReviewSent(count)),
            if (count > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(l10n.reviewInboxTitle),
                onPressed: () => Navigator.of(context).push(
                  CupertinoStyleRoute(
                    page: const ReviewInboxPage(),
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _EnvelopeSection(
            title: l10n.knowledgeExportIncludedCount(snapshot.includedCount),
            envelopes: snapshot.included,
            excludedReasons: const <String, String>{},
          ),
          const SizedBox(height: 12),
          _EnvelopeSection(
            title: l10n.knowledgeExportExcludedCount(snapshot.excludedCount),
            envelopes: snapshot.excluded,
            excludedReasons: snapshot.excludedReasons,
          ),
        ],
      ),
    );
  }
}

class _RemoteSyncStatusPanel extends StatelessWidget {
  const _RemoteSyncStatusPanel({required this.status});

  final KnowledgeRemoteSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final title = switch (status) {
      KnowledgeRemoteSyncStatus.notPreviewed =>
        l10n.knowledgeExportRemoteStatusNotPreviewed,
      KnowledgeRemoteSyncStatus.reviewRequired =>
        l10n.knowledgeExportRemoteStatusReviewRequired,
      KnowledgeRemoteSyncStatus.readyToUpload =>
        l10n.knowledgeExportRemoteStatusReadyToUpload,
      KnowledgeRemoteSyncStatus.uploaded =>
        l10n.knowledgeExportRemoteStatusUploaded,
      KnowledgeRemoteSyncStatus.repreviewRequired =>
        l10n.knowledgeExportRemoteStatusRepreviewRequired,
      KnowledgeRemoteSyncStatus.concurrencyGuardUnavailable =>
        l10n.knowledgeExportRemoteStatusConcurrencyGuardUnavailable,
      KnowledgeRemoteSyncStatus.failed =>
        l10n.knowledgeExportRemoteStatusFailed,
    };
    final body = switch (status) {
      KnowledgeRemoteSyncStatus.notPreviewed =>
        l10n.knowledgeExportRemoteStatusNotPreviewedBody,
      KnowledgeRemoteSyncStatus.reviewRequired =>
        l10n.knowledgeExportRemoteStatusReviewRequiredBody,
      KnowledgeRemoteSyncStatus.readyToUpload =>
        l10n.knowledgeExportRemoteStatusReadyToUploadBody,
      KnowledgeRemoteSyncStatus.uploaded =>
        l10n.knowledgeExportRemoteStatusUploadedBody,
      KnowledgeRemoteSyncStatus.repreviewRequired =>
        l10n.knowledgeExportRemoteStatusRepreviewRequiredBody,
      KnowledgeRemoteSyncStatus.concurrencyGuardUnavailable =>
        l10n.knowledgeExportRemoteStatusConcurrencyGuardUnavailableBody,
      KnowledgeRemoteSyncStatus.failed =>
        l10n.knowledgeExportRemoteStatusFailedBody,
    };

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: ClaudePalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _statusIcon(status),
              size: 18,
              color: ClaudePalette.accent(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(KnowledgeRemoteSyncStatus status) {
    return switch (status) {
      KnowledgeRemoteSyncStatus.notPreviewed => Icons.cloud_queue_outlined,
      KnowledgeRemoteSyncStatus.reviewRequired => Icons.fact_check_outlined,
      KnowledgeRemoteSyncStatus.readyToUpload => Icons.cloud_done_outlined,
      KnowledgeRemoteSyncStatus.uploaded => Icons.cloud_upload_outlined,
      KnowledgeRemoteSyncStatus.repreviewRequired => Icons.sync_problem,
      KnowledgeRemoteSyncStatus.concurrencyGuardUnavailable =>
        Icons.gpp_maybe_outlined,
      KnowledgeRemoteSyncStatus.failed => Icons.error_outline,
    };
  }
}

class _RemotePreviewSection extends ConsumerWidget {
  const _RemotePreviewSection({
    required this.preview,
    required this.busy,
  });

  final KnowledgeRemoteSyncPreview preview;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
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
            Text(
              l10n.knowledgeExportRemotePreviewTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TinyChip(
                  label: l10n.knowledgeExportRemoteCount(
                    preview.remoteCount,
                  ),
                ),
                _TinyChip(
                  label: l10n.knowledgeExportIncomingCount(
                    preview.incomingCount,
                  ),
                ),
                _TinyChip(
                  label: l10n.knowledgeExportOutgoingCount(
                    preview.outgoingCount,
                  ),
                ),
                _TinyChip(
                  label: l10n.knowledgeExportRemoteConflictCount(
                    preview.conflictCount,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PolicyNote(
              text: l10n.knowledgeExportRemoteBundlePath(preview.remotePath),
            ),
            if (preview.incomingCount > 0) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.move_to_inbox_outlined),
                label: Text(l10n.knowledgeExportSendRemoteIncomingToReview),
                onPressed: busy
                    ? null
                    : () => ref
                        .read(knowledgeAssetExportProvider.notifier)
                        .submitRemoteIncomingToReview(),
              ),
            ],
            if (preview.incoming.any(
              (envelope) =>
                  envelope.entityType == KnowledgeSyncEntityType.reviewHistory,
            )) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.history_edu_outlined),
                label:
                    Text(l10n.knowledgeExportSendRemoteReviewHistoryToReview),
                onPressed: busy
                    ? null
                    : () => ref
                        .read(knowledgeAssetExportProvider.notifier)
                        .submitRemoteReviewHistoryToReview(),
              ),
            ],
            if (preview.conflictCount > 0) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.rule_folder_outlined),
                label: Text(
                  l10n.knowledgeExportStageRemoteCardConflictsToReview,
                ),
                onPressed: busy
                    ? null
                    : () => ref
                        .read(knowledgeAssetExportProvider.notifier)
                        .stageRemoteKnowledgeCardConflictsToReview(),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(l10n.knowledgeExportSendRemoteConflictsToReview),
                onPressed: busy
                    ? null
                    : () => ref
                        .read(knowledgeAssetExportProvider.notifier)
                        .submitRemoteConflictsToReview(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EnvelopeSection extends StatelessWidget {
  const _EnvelopeSection({
    required this.title,
    required this.envelopes,
    required this.excludedReasons,
  });

  final String title;
  final List<KnowledgeSyncEnvelope> envelopes;
  final Map<String, String> excludedReasons;

  @override
  Widget build(BuildContext context) {
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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (envelopes.isEmpty)
              Text(
                '-',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              )
            else
              for (final envelope in envelopes.take(8)) ...[
                _EnvelopeRow(
                  envelope: envelope,
                  reason: excludedReasons[envelope.id],
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({required this.envelope, this.reason});

  final KnowledgeSyncEnvelope envelope;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      envelope.entityType.asString,
      if (reason != null) reason!,
      if (envelope.requiresConflictReview)
        envelope.conflictReason ?? envelope.conflictStatus.asString,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          envelope.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
      ],
    );
  }
}

class _KnowledgeAssetExportEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ios_share_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              l10n.knowledgeExportEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.knowledgeExportEmptyBody,
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
}

class _KnowledgeAssetExportError extends ConsumerWidget {
  const _KnowledgeAssetExportError({required this.error});

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
            Text(l10n.knowledgeExportLoadFailed),
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
                  ref.read(knowledgeAssetExportProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyNote extends StatelessWidget {
  const _PolicyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ClaudePalette.secondary(context),
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
