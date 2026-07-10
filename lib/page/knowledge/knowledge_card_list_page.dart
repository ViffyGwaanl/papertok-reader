import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/knowledge/knowledge_card_detail_page.dart';

/// Home for saved knowledge cards (S2 batch 2). Before this page existed,
/// a card saved from the reader/AI chat was only reachable through the
/// save-time SnackBar — dismiss it and the card was invisible forever.
typedef KnowledgeCardsLoader = Future<List<KnowledgeCard>> Function(
    KnowledgeCardReviewState? filter);

class KnowledgeCardListPage extends ConsumerStatefulWidget {
  const KnowledgeCardListPage({super.key, this.store, this.loader});

  /// Injectable for tests; defaults to the app store.
  final KnowledgeCardStore? store;

  /// Test seam: widget tests run under FakeAsync where real file IO never
  /// resolves, so they inject a synchronous loader instead.
  final KnowledgeCardsLoader? loader;

  @override
  ConsumerState<KnowledgeCardListPage> createState() =>
      _KnowledgeCardListPageState();
}

class _KnowledgeCardListPageState extends ConsumerState<KnowledgeCardListPage> {
  late final KnowledgeCardStore _store = widget.store ?? KnowledgeCardStore();
  KnowledgeCardReviewState? _filter;
  late Future<List<KnowledgeCard>> _cards = _load();

  Future<List<KnowledgeCard>> _load() => widget.loader != null
      ? widget.loader!(_filter)
      : _store.list(reviewState: _filter);

  void _refresh() {
    setState(() {
      _cards = _load();
    });
  }

  String stateLabel(L10n l10n, KnowledgeCardReviewState state) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsSubpageScaffold(
      title: l10n.knowledgeCardListTitle,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _filterChip(l10n.knowledgeCardFilterAll, null),
                for (final state in KnowledgeCardReviewState.values)
                  _filterChip(stateLabel(l10n, state), state),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<KnowledgeCard>>(
              future: _cards,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final cards = snapshot.data ?? const <KnowledgeCard>[];
                if (cards.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        l10n.knowledgeCardListEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _cardTile(context, l10n, cards[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, KnowledgeCardReviewState? state) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == state,
        onSelected: (_) {
          _filter = state;
          _refresh();
        },
      ),
    );
  }

  Widget _cardTile(BuildContext context, L10n l10n, KnowledgeCard card) {
    final quote = card.quote.trim();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: ClaudePalette.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ClaudePalette.divider(context)),
      ),
      child: ListTile(
        title: Text(
          card.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quote.isNotEmpty)
              Text(quote, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              stateLabel(l10n, card.reviewState),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => KnowledgeCardDetailPage(
                card: card,
                store: _store,
              ),
            ),
          );
          if (mounted) _refresh();
        },
      ),
    );
  }
}
