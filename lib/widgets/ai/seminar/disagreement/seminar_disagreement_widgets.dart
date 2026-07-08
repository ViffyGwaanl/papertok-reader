import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';

typedef SeminarDisagreementRoleLabelsBuilder = String Function(
  List<String> roleIds,
);
typedef SeminarDisagreementRoleLabelBuilder = String Function(String roleId);
typedef SeminarDisagreementEvidenceTileBuilder = Widget Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);
typedef SeminarDisagreementCountLabelBuilder = String Function(
  int count, {
  required String zhUnit,
  required String enSingular,
  required String enPlural,
});

class SeminarSnapshotDisagreementDetails extends StatelessWidget {
  const SeminarSnapshotDisagreementDetails({
    required this.details,
    required this.zh,
    required this.roleLabelsBuilder,
    required this.evidenceTileBuilder,
    super.key,
  });

  final List<AiSeminarRunCardDisagreementDetail> details;
  final bool zh;
  final SeminarDisagreementRoleLabelsBuilder roleLabelsBuilder;
  final SeminarDisagreementEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in details)
          Padding(
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
                    SeminarSnapshotExpandableText(
                      detail.text.trim(),
                      collapsedMaxLines: 3,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.fg(context),
                            height: 1.32,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (detail.roleIds
                        .where((roleId) => roleId.trim().isNotEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '关联角色' : 'Linked roles',
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleLabelsBuilder(detail.roleIds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (detail.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '关联证据' : 'Linked evidence',
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in detail.evidenceRefs.where((item) => !item.isEmpty))
                        evidenceTileBuilder(evidence),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      detail.agentRunId,
                      parentRunId: detail.parentRunId,
                      zh: zh,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SeminarSnapshotContradictionScanTiles extends StatelessWidget {
  const SeminarSnapshotContradictionScanTiles({
    required this.parts,
    required this.zh,
    required this.roleLabelsBuilder,
    required this.countLabelBuilder,
    required this.evidenceTileBuilder,
    super.key,
  });

  final List<AiSeminarRunCardMessagePart> parts;
  final bool zh;
  final SeminarDisagreementRoleLabelsBuilder roleLabelsBuilder;
  final SeminarDisagreementCountLabelBuilder countLabelBuilder;
  final SeminarDisagreementEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    final evidenceGapParts = parts
        .where(_seminarContradictionScanIsEvidenceGap)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotContradictionScanOverviewTile(
          parts: parts,
          zh: zh,
          countLabelBuilder: countLabelBuilder,
        ),
        const SizedBox(height: 6),
        if (evidenceGapParts.length > 1) ...[
          SeminarSnapshotContradictionGapSummaryTile(
            parts: evidenceGapParts,
            zh: zh,
            countLabelBuilder: countLabelBuilder,
          ),
          const SizedBox(height: 6),
        ],
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(
                      alpha: 0.24,
                    ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.radar_outlined,
                          size: 16,
                          color: ClaudePalette.accent(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            zh ? '分歧扫描' : 'Contradiction scan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (_seminarContradictionScanLabel(part.label, zh) !=
                        null) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '扫描结论' : 'Scan result',
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarContradictionScanLabel(part.label, zh)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.text?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.fg(context),
                              height: 1.32,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.roleIds
                        .where((roleId) => roleId.trim().isNotEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '关联角色' : 'Linked roles',
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleLabelsBuilder(part.roleIds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (part.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '关联证据' : 'Linked evidence',
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in part.evidenceRefs.where((item) => !item.isEmpty))
                        evidenceTileBuilder(evidence),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: zh,
                    ),
                    if (_seminarContradictionScanNeedsEvidence(part)) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '缺少可追踪证据' : 'Traceable evidence missing',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SeminarSnapshotContradictionScanOverviewTile extends StatelessWidget {
  const SeminarSnapshotContradictionScanOverviewTile({
    required this.parts,
    required this.zh,
    required this.countLabelBuilder,
    super.key,
  });

  final List<AiSeminarRunCardMessagePart> parts;
  final bool zh;
  final SeminarDisagreementCountLabelBuilder countLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final evidenceGapCount =
        parts.where(_seminarContradictionScanIsEvidenceGap).length;
    final evidenceBackedCount = parts
        .where(
          (part) =>
              !_seminarContradictionScanIsEvidenceGap(part) &&
              _seminarContradictionScanHasEvidence(part),
        )
        .length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.query_stats_outlined,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zh ? '分歧扫描概览' : 'Contradiction scan overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SeminarSnapshotTinyChip(
                  countLabelBuilder(
                    parts.length,
                    zhUnit: '条扫描',
                    enSingular: 'scan',
                    enPlural: 'scans',
                  ),
                ),
                SeminarSnapshotTinyChip(
                  countLabelBuilder(
                    evidenceGapCount,
                    zhUnit: '条证据缺口',
                    enSingular: 'evidence gap',
                    enPlural: 'evidence gaps',
                  ),
                ),
                SeminarSnapshotTinyChip(
                  countLabelBuilder(
                    evidenceBackedCount,
                    zhUnit: '条已有证据',
                    enSingular: 'evidence-backed scan',
                    enPlural: 'evidence-backed scans',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SeminarSnapshotContradictionGapSummaryTile extends StatelessWidget {
  const SeminarSnapshotContradictionGapSummaryTile({
    required this.parts,
    required this.zh,
    required this.countLabelBuilder,
    super.key,
  });

  final List<AiSeminarRunCardMessagePart> parts;
  final bool zh;
  final SeminarDisagreementCountLabelBuilder countLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final previewTexts = parts
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.priority_high_outlined,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zh ? '证据缺口汇总' : 'Evidence gap summary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                SeminarSnapshotTinyChip(
                  countLabelBuilder(
                    parts.length,
                    zhUnit: '条证据缺口',
                    enSingular: 'evidence gap',
                    enPlural: 'evidence gaps',
                  ),
                ),
              ],
            ),
            if (previewTexts.isNotEmpty) ...[
              const SizedBox(height: 7),
              for (final text in previewTexts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SeminarSnapshotExpandableText(
                    text,
                    collapsedMaxLines: 2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.3,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class SeminarSnapshotDisagreementRebuttalTiles extends StatelessWidget {
  const SeminarSnapshotDisagreementRebuttalTiles({
    required this.parts,
    required this.zh,
    required this.roleLabelBuilder,
    required this.evidenceTileBuilder,
    super.key,
  });

  final List<AiSeminarRunCardMessagePart> parts;
  final bool zh;
  final SeminarDisagreementRoleLabelBuilder roleLabelBuilder;
  final SeminarDisagreementEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ClaudePalette.accentTint(context).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.record_voice_over_outlined,
                          size: 16,
                          color: ClaudePalette.accent(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            zh ? '分歧反驳回合' : 'Disagreement rebuttal turn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (part.roleId?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(zh ? '角色' : 'Role'),
                      const SizedBox(height: 3),
                      Text(
                        roleLabelBuilder(part.roleId!.trim()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (part.label?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '目标分歧' : 'Target disagreement',
                      ),
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        part.label!.trim(),
                        collapsedMaxLines: 3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.fg(context),
                              height: 1.32,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.text?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    if (part.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '关联证据' : 'Linked evidence',
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in part.evidenceRefs.where((item) => !item.isEmpty))
                        evidenceTileBuilder(evidence),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: zh,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String? _seminarContradictionScanLabel(String? label, bool zh) {
  switch (label?.trim()) {
    case 'evidence-gap':
      return zh ? '证据缺口' : 'Evidence gap';
    default:
      return null;
  }
}

bool _seminarContradictionScanNeedsEvidence(
  AiSeminarRunCardMessagePart part,
) {
  return _seminarContradictionScanIsEvidenceGap(part) &&
      !_seminarContradictionScanHasEvidence(part);
}

bool _seminarContradictionScanIsEvidenceGap(
  AiSeminarRunCardMessagePart part,
) {
  return part.label?.trim() == 'evidence-gap';
}

bool _seminarContradictionScanHasEvidence(
  AiSeminarRunCardMessagePart part,
) {
  return part.evidenceRefs.where((item) => !item.isEmpty).isNotEmpty;
}
