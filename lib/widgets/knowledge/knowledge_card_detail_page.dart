import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

void showKnowledgeCardSavedSnackBar(
  BuildContext context, {
  required String message,
  required KnowledgeCard card,
}) {
  final l10n = L10n.of(context);
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: l10n.knowledgeCardViewAction,
          onPressed: () => openKnowledgeCardDetailPage(context, card),
        ),
      ),
    );
}

void openKnowledgeCardDetailPage(BuildContext context, KnowledgeCard card) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => KnowledgeCardDetailPage(card: card),
    ),
  );
}

class KnowledgeCardDetailPage extends ConsumerStatefulWidget {
  const KnowledgeCardDetailPage({super.key, required this.card, this.store});

  final KnowledgeCard card;

  /// Injectable for tests; defaults to the app store.
  final KnowledgeCardStore? store;

  @override
  ConsumerState<KnowledgeCardDetailPage> createState() =>
      _KnowledgeCardDetailPageState();
}

class _KnowledgeCardDetailPageState
    extends ConsumerState<KnowledgeCardDetailPage> {
  late KnowledgeCard _card = widget.card;
  late final KnowledgeCardStore _store = widget.store ?? KnowledgeCardStore();
  bool _busy = false;

  String _stateLabel(L10n l10n, KnowledgeCardReviewState state) {
    switch (state) {
      case KnowledgeCardReviewState.draft:
        return l10n.knowledgeCardStateDraft;
      case KnowledgeCardReviewState.pending:
        return l10n.knowledgeCardStatePending;
      case KnowledgeCardReviewState.approved:
        return l10n.knowledgeCardStateApproved;
      case KnowledgeCardReviewState.dismissed:
        return l10n.knowledgeCardStateDismissed;
      case KnowledgeCardReviewState.applied:
        return l10n.knowledgeCardStateApplied;
    }
  }

  PaperReaderReaderIntent? get _firstIntent => _card.sourceRefs
      .map(PaperReaderReaderIntent.fromSourceRef)
      .whereType<PaperReaderReaderIntent>()
      .firstOrNull;

  Future<void> _openSource() async {
    final intent = _firstIntent;
    if (intent == null) {
      showPaperReaderSourceUnavailable(
        context,
        _card.sourceRefs,
        L10n.of(context).knowledgeCardDetailNoSources,
      );
      return;
    }
    await openPaperReaderSource(ref, intent.toUri());
  }

  Future<void> _submitForReview() async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await _store.upsert(
        _card.copyWith(
          reviewState: KnowledgeCardReviewState.pending,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await ReviewItemStore().upsert(
        KnowledgeCardReviewAdapter.fromKnowledgeCard(updated),
      );
      if (!mounted) return;
      setState(() => _card = updated);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.knowledgeCardSubmittedForReview)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = L10n.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.knowledgeCardDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final removed = await _store.removeDraftCandidate(_card.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (removed) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final canSubmit = _card.reviewState == KnowledgeCardReviewState.draft;
    final canDelete = (_card.reviewState == KnowledgeCardReviewState.draft ||
            _card.reviewState == KnowledgeCardReviewState.pending) &&
        !_card.isUserAsset;

    return Scaffold(
      backgroundColor: ClaudePalette.bg(context),
      appBar: AppBar(
        title: Text(l10n.knowledgeCardDetailTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _DetailSection(
            title: _card.title,
            body: _card.explanation,
            emphasized: true,
          ),
          if (_card.quote.trim().isNotEmpty)
            _DetailSection(
              title: l10n.knowledgeCardDetailQuote,
              body: _card.quote.trim(),
            ),
          _DetailSection(
            title: l10n.knowledgeCardDetailState,
            body: _stateLabel(l10n, _card.reviewState),
          ),
          _DetailSection(
            title: l10n.knowledgeCardDetailSources,
            body: _sourceText(l10n, _card.sourceRefs),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(l10n.reviewInboxOpenSourceAction),
                onPressed: _busy ? null : _openSource,
              ),
              if (canSubmit)
                OutlinedButton.icon(
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(l10n.knowledgeCardSubmitReviewAction),
                  onPressed: _busy ? null : _submitForReview,
                ),
              if (canDelete)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.commonDelete),
                  onPressed: _busy ? null : _delete,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceText(L10n l10n, List<SourceRef> refs) {
    final lines = refs
        .map((ref) => ref.sourceTextSnippet?.trim().isNotEmpty == true
            ? ref.sourceTextSnippet!.trim()
            : ref.locationLabel?.trim() ?? '')
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return lines.isEmpty ? l10n.knowledgeCardDetailNoSources : lines.join('\n');
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.body,
    this.emphasized = false,
  });

  final String title;
  final String body;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: ClaudePalette.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ClaudePalette.fg(context),
                  ),
            ),
            if (body.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                body.trim(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                      color: emphasized
                          ? ClaudePalette.fg(context)
                          : ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
