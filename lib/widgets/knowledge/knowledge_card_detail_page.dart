import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
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

class KnowledgeCardDetailPage extends StatelessWidget {
  const KnowledgeCardDetailPage({super.key, required this.card});

  final KnowledgeCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
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
            title: card.title,
            body: card.explanation,
            emphasized: true,
          ),
          if (card.quote.trim().isNotEmpty)
            _DetailSection(
              title: l10n.knowledgeCardDetailQuote,
              body: card.quote.trim(),
            ),
          _DetailSection(
            title: l10n.knowledgeCardDetailState,
            body: card.reviewState.asString,
          ),
          _DetailSection(
            title: l10n.knowledgeCardDetailSources,
            body: _sourceText(l10n, card.sourceRefs),
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
