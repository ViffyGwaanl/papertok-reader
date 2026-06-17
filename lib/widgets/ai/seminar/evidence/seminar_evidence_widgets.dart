import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_evidence_numbering.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';

typedef SeminarEvidenceSourceActionBuilder = Widget? Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);

class SeminarSnapshotCompactEvidenceRows extends StatelessWidget {
  const SeminarSnapshotCompactEvidenceRows({
    required this.evidenceRefs,
    required this.linkedEvidenceLabel,
    required this.missingSourceLabel,
    required this.sourceActionBuilder,
    super.key,
  });

  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final String linkedEvidenceLabel;
  final String missingSourceLabel;
  final SeminarEvidenceSourceActionBuilder sourceActionBuilder;

  @override
  Widget build(BuildContext context) {
    final visibleEvidenceRefs =
        evidenceRefs.where((item) => !item.isEmpty).toList(growable: false);
    if (visibleEvidenceRefs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        SeminarSnapshotDetailLabel(linkedEvidenceLabel),
        const SizedBox(height: 3),
        for (final evidence in visibleEvidenceRefs)
          SeminarSnapshotCompactEvidenceRow(
            evidence: evidence,
            sourceAction: sourceActionBuilder(evidence),
            missingSourceLabel: missingSourceLabel,
          ),
      ],
    );
  }
}

class SeminarSnapshotCompactEvidenceRow extends StatelessWidget {
  const SeminarSnapshotCompactEvidenceRow({
    required this.evidence,
    required this.missingSourceLabel,
    this.sourceAction,
    super.key,
  });

  final AiSeminarRunCardEvidenceSnapshot evidence;
  final String missingSourceLabel;
  final Widget? sourceAction;

  @override
  Widget build(BuildContext context) {
    final missingSourceChip = sourceAction == null
        ? SeminarSnapshotMissingSourceChip(
            missingSourceLabel,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              evidence.snippet.trim().isNotEmpty
                  ? evidence.snippet.trim()
                  : evidence.title.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.25,
                  ),
            ),
          ),
          if (sourceAction != null) ...[
            const SizedBox(width: 6),
            sourceAction!,
          ] else if (missingSourceChip != null) ...[
            const SizedBox(width: 6),
            missingSourceChip,
          ],
        ],
      ),
    );
  }
}

class SeminarSnapshotEvidenceTile extends StatelessWidget {
  const SeminarSnapshotEvidenceTile(
    this.evidence, {
    required this.zh,
    required this.missingSourceLabel,
    this.sourceAction,
    this.fallbackIndex,
    this.expandableSnippet = false,
    super.key,
  });

  final AiSeminarRunCardEvidenceSnapshot evidence;
  final bool zh;
  final String missingSourceLabel;
  final Widget? sourceAction;
  final int? fallbackIndex;
  final bool expandableSnippet;

  @override
  Widget build(BuildContext context) {
    final title = evidence.title.trim();
    final snippet = evidence.snippet.trim();
    final numberChip = _evidenceNumberChip(context);
    final sourceStatus =
        sourceAction ?? SeminarSnapshotMissingSourceChip(missingSourceLabel);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty || numberChip != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (numberChip != null) ...[
                      numberChip,
                      const SizedBox(width: 6),
                    ],
                    if (title.isNotEmpty)
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: ClaudePalette.fg(context),
                                  ),
                        ),
                      ),
                    if (title.isEmpty) const Spacer(),
                    const SizedBox(width: 6),
                    sourceStatus,
                  ],
                ),
              if (snippet.isNotEmpty) ...[
                if (title.isNotEmpty || numberChip != null)
                  const SizedBox(height: 3),
                if (expandableSnippet)
                  SeminarSnapshotExpandableText(
                    snippet,
                    collapsedMaxLines: 3,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.32,
                        ),
                  )
                else
                  Text(
                    snippet,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.32,
                        ),
                  ),
              ],
              if (title.isEmpty) ...[
                if (snippet.isNotEmpty) const SizedBox(height: 4),
                if (numberChip == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: sourceStatus,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _evidenceNumberChip(BuildContext context) {
    final label = seminarEvidenceLabel(
      id: evidence.id,
      fallbackIndex: fallbackIndex,
      zh: zh,
    );
    if (label == null) return null;
    return Chip(
      key: ValueKey(
        'seminar-evidence-number-${evidence.id ?? label}-$fallbackIndex',
      ),
      avatar: const Icon(Icons.format_list_numbered, size: 14),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class SeminarEvidenceReferenceChips extends StatelessWidget {
  const SeminarEvidenceReferenceChips({
    required this.evidenceRefs,
    required this.zh,
    required this.onEvidencePressed,
    super.key,
  });

  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final bool zh;
  final ValueChanged<AiSeminarRunCardEvidenceSnapshot> onEvidencePressed;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (var index = 0; index < evidenceRefs.length; index++) {
      final chip = _referenceChip(
        context,
        evidenceRefs[index],
        keyIndex: index,
      );
      if (chip != null) chips.add(chip);
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget? _referenceChip(
    BuildContext context,
    AiSeminarRunCardEvidenceSnapshot evidence, {
    required int keyIndex,
  }) {
    final label = seminarEvidenceLabel(
      id: evidence.id,
      zh: zh,
    );
    if (label == null) return null;
    final keyId =
        evidence.id?.trim().isNotEmpty == true ? evidence.id!.trim() : label;
    return ActionChip(
      key: ValueKey('seminar-evidence-ref-$keyId-$keyIndex'),
      avatar: const Icon(Icons.format_list_numbered, size: 14),
      label: Text(label),
      onPressed: () => onEvidencePressed(evidence),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
