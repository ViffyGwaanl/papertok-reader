import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_unavailable_reason_label.dart';

class SourceRefEvidenceList extends StatelessWidget {
  const SourceRefEvidenceList({
    super.key,
    required this.sourceRefs,
    this.maxItems = 3,
  });

  final List<SourceRef> sourceRefs;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final refs = sourceRefs
        .where((ref) => ref.hasEvidence)
        .take(maxItems)
        .toList(growable: false);
    if (refs.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_quote, size: 16),
                const SizedBox(width: 6),
                Text(
                  l10n.conceptGraphEvidenceTitle,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < refs.length; index++) ...[
              _SourceRefEvidenceTile(sourceRef: refs[index]),
              if (index < refs.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceRefEvidenceTile extends StatelessWidget {
  const _SourceRefEvidenceTile({required this.sourceRef});

  final SourceRef sourceRef;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final text = _primaryText(l10n, sourceRef);
    final subtitle = _subtitle(l10n, sourceRef);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          sourceRef.canJumpBack
              ? Icons.link_outlined
              : sourceRef.hasUnavailableReason
                  ? Icons.link_off_outlined
                  : Icons.notes_outlined,
          size: 16,
          color: ClaudePalette.secondary(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _primaryText(L10n l10n, SourceRef sourceRef) {
    final snippet = sourceRef.sourceTextSnippet?.trim();
    if (snippet != null && snippet.isNotEmpty) return snippet;
    final unavailableReason = sourceRef.unavailableReason?.trim();
    if (unavailableReason != null && unavailableReason.isNotEmpty) {
      return localizedSourceRefUnavailableReason(l10n, unavailableReason);
    }
    return sourceRef.sourceKind.asString;
  }

  String _subtitle(L10n l10n, SourceRef sourceRef) {
    final hasSnippet = sourceRef.sourceTextSnippet != null &&
        sourceRef.sourceTextSnippet!.trim().isNotEmpty;
    return [
      sourceRef.sourceTitle,
      sourceRef.locationLabel,
      if (hasSnippet &&
          !sourceRef.canJumpBack &&
          sourceRef.unavailableReason?.trim().isNotEmpty == true)
        localizedSourceRefUnavailableReason(
          l10n,
          sourceRef.unavailableReason!,
        ),
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
  }
}
