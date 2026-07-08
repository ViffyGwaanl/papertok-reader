import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/disagreement/seminar_disagreement_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/evidence/seminar_evidence_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';

typedef SeminarTimelinePartBuilder = Widget Function(
  AiSeminarRunCardMessagePart part,
  int? roleTurnNumber,
);
typedef SeminarTimelinePartWidgetBuilder = Widget Function(
  AiSeminarRunCardMessagePart part,
);
typedef SeminarTimelineEvidenceTileBuilder = Widget Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);
typedef SeminarTimelineEvidenceSourceActionBuilder = Widget? Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);
typedef SeminarTimelineThinkingContextLabelBuilder = String? Function(
  AiSeminarRunCardMessagePart part,
);
typedef SeminarTimelineCompletedAtLabelBuilder = String? Function(
  int? completedAt,
);
typedef SeminarTimelineReviewLabelBuilder = String Function(String? label);
typedef SeminarTimelineReviewTextBuilder = String Function(
  AiSeminarRunCardMessagePart part,
);
typedef SeminarTimelineArtifactChipLabelBuilder = String Function(
  String actionId,
);
typedef SeminarTimelineArtifactDisplayTextBuilder = String Function(
  String rawText,
);
typedef SeminarTimelineArtifactStatusLabelBuilder = String? Function(
  String? status,
);
typedef SeminarTimelineArtifactCompletedAtLabelBuilder = String? Function(
  String? status,
  int? completedAt,
);
typedef SeminarTimelineArtifactDetailLabelBuilder = String Function(
  String? status,
);

class SeminarSnapshotNativeTimeline extends StatelessWidget {
  const SeminarSnapshotNativeTimeline({
    required this.parts,
    required this.sessionId,
    required this.hiddenPartCount,
    required this.canToggleExpansion,
    required this.isExpanded,
    required this.zh,
    required this.partBuilder,
    required this.onToggleExpansion,
    super.key,
  });

  final List<AiSeminarRunCardMessagePart> parts;
  final String? sessionId;
  final int hiddenPartCount;
  final bool canToggleExpansion;
  final bool isExpanded;
  final bool zh;
  final SeminarTimelinePartBuilder partBuilder;
  final VoidCallback onToggleExpansion;

  @override
  Widget build(BuildContext context) {
    var roleTurnNumber = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.timeline_outlined,
          zh ? '研讨流' : 'Seminar stream',
        ),
        const SizedBox(height: 6),
        for (final part in parts)
          partBuilder(
            part,
            part.type.trim() == 'role_turn' ? ++roleTurnNumber : null,
          ),
        if (hiddenPartCount > 0 ||
            (canToggleExpansion && sessionId != null && isExpanded))
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hiddenPartCount > 0)
                Text(
                  zh
                      ? '还有 $hiddenPartCount 个研讨片段可在分类视图中查看。'
                      : '$hiddenPartCount more Seminar parts are available in tabs.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                      ),
                ),
              if (canToggleExpansion && sessionId != null)
                TextButton.icon(
                  key: ValueKey(
                    'seminar-chat-card-native-timeline-toggle-$sessionId',
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onToggleExpansion,
                  icon: Icon(
                    isExpanded
                        ? Icons.unfold_less_outlined
                        : Icons.unfold_more_outlined,
                    size: 16,
                  ),
                  label: Text(
                    zh
                        ? isExpanded
                            ? '收起研讨流'
                            : '展开全部研讨流'
                        : isExpanded
                            ? 'Collapse Seminar stream'
                            : 'Expand full Seminar stream',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class SeminarSnapshotNativeTimelinePart extends StatelessWidget {
  const SeminarSnapshotNativeTimelinePart({
    required this.part,
    required this.zh,
    required this.showInlineEvidence,
    required this.showTraceDetails,
    required this.roleTurnNumber,
    required this.toolCallBuilder,
    required this.roleTurnBuilder,
    required this.rolePartialBuilder,
    required this.directorStateBuilder,
    required this.agentStatusBuilder,
    required this.readerTurnBuilder,
    required this.readerComposerBuilder,
    required this.thinkingContextLabelBuilder,
    required this.thinkingCompletedAtLabelBuilder,
    required this.roleLabelsBuilder,
    required this.roleLabelBuilder,
    required this.countLabelBuilder,
    required this.reviewTriageLabelBuilder,
    required this.reviewTriageTextBuilder,
    required this.artifactChipLabelBuilder,
    required this.artifactDisplayTextBuilder,
    required this.artifactStatusLabelBuilder,
    required this.artifactCompletedAtLabelBuilder,
    required this.artifactDetailLabelBuilder,
    required this.evidenceTileBuilder,
    required this.linkedEvidenceLabel,
    required this.missingSourceLabel,
    required this.evidenceSourceActionBuilder,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final bool showInlineEvidence;
  final bool showTraceDetails;
  final int? roleTurnNumber;
  final SeminarTimelinePartWidgetBuilder toolCallBuilder;
  final SeminarTimelinePartBuilder roleTurnBuilder;
  final SeminarTimelinePartWidgetBuilder rolePartialBuilder;
  final SeminarTimelinePartWidgetBuilder directorStateBuilder;
  final SeminarTimelinePartWidgetBuilder agentStatusBuilder;
  final SeminarTimelinePartWidgetBuilder readerTurnBuilder;
  final SeminarTimelinePartWidgetBuilder readerComposerBuilder;
  final SeminarTimelineThinkingContextLabelBuilder thinkingContextLabelBuilder;
  final SeminarTimelineCompletedAtLabelBuilder thinkingCompletedAtLabelBuilder;
  final SeminarDisagreementRoleLabelsBuilder roleLabelsBuilder;
  final SeminarDisagreementRoleLabelBuilder roleLabelBuilder;
  final SeminarDisagreementCountLabelBuilder countLabelBuilder;
  final SeminarTimelineReviewLabelBuilder reviewTriageLabelBuilder;
  final SeminarTimelineReviewTextBuilder reviewTriageTextBuilder;
  final SeminarTimelineArtifactChipLabelBuilder artifactChipLabelBuilder;
  final SeminarTimelineArtifactDisplayTextBuilder artifactDisplayTextBuilder;
  final SeminarTimelineArtifactStatusLabelBuilder artifactStatusLabelBuilder;
  final SeminarTimelineArtifactCompletedAtLabelBuilder
      artifactCompletedAtLabelBuilder;
  final SeminarTimelineArtifactDetailLabelBuilder artifactDetailLabelBuilder;
  final SeminarTimelineEvidenceTileBuilder evidenceTileBuilder;
  final String linkedEvidenceLabel;
  final String missingSourceLabel;
  final SeminarTimelineEvidenceSourceActionBuilder evidenceSourceActionBuilder;

  @override
  Widget build(BuildContext context) {
    switch (part.type.trim()) {
      case 'seminar_run_setup':
        return SeminarSnapshotRunSetupPartTile(part: part, zh: zh);
      case 'tool_call':
        return toolCallBuilder(part);
      case 'evidence':
      case 'evidence_bundle':
        return _SeminarSnapshotEvidenceBundlePartTile(
          part: part,
          zh: zh,
          evidenceTileBuilder: evidenceTileBuilder,
        );
      case 'role_turn':
        return roleTurnBuilder(part, roleTurnNumber);
      case 'role_partial':
        return rolePartialBuilder(part);
      case 'director_state':
        return directorStateBuilder(part);
      case 'agent_status':
        return agentStatusBuilder(part);
      case 'thinking':
        return SeminarSnapshotNativeTextPartTile(
          icon: Icons.psychology_outlined,
          label: zh ? '思考' : 'Thinking',
          contextLabel: thinkingContextLabelBuilder(part),
          text: part.text?.trim() ?? part.label?.trim() ?? '',
          detailChipLabel: thinkingCompletedAtLabelBuilder(part.completedAt),
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
          zh: zh,
          linkedEvidenceLabel: linkedEvidenceLabel,
          missingSourceLabel: missingSourceLabel,
          evidenceSourceActionBuilder: evidenceSourceActionBuilder,
        );
      case 'reader_turn':
        return readerTurnBuilder(part);
      case 'reader_composer':
        return readerComposerBuilder(part);
      case 'synthesis':
        return SeminarSnapshotNativeTextPartTile(
          icon: Icons.auto_awesome_outlined,
          label: zh ? '研讨总结' : 'Seminar summary',
          text: part.text?.trim() ?? '',
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
          evidenceRefs: showInlineEvidence
              ? part.evidenceRefs
              : const <AiSeminarRunCardEvidenceSnapshot>[],
          zh: zh,
          linkedEvidenceLabel: linkedEvidenceLabel,
          missingSourceLabel: missingSourceLabel,
          evidenceSourceActionBuilder: evidenceSourceActionBuilder,
        );
      case 'disagreement':
        return SeminarSnapshotDisagreementDetails(
          details: [
            AiSeminarRunCardDisagreementDetail(
              text: part.text ?? '',
              agentRunId: part.agentRunId,
              parentRunId: part.parentRunId,
              roleIds: part.roleIds,
              evidenceRefs: part.evidenceRefs,
            ),
          ],
          zh: zh,
          roleLabelsBuilder: roleLabelsBuilder,
          evidenceTileBuilder: evidenceTileBuilder,
        );
      case 'contradiction_scan':
        return SeminarSnapshotContradictionScanTiles(
          parts: [part],
          zh: zh,
          roleLabelsBuilder: roleLabelsBuilder,
          countLabelBuilder: countLabelBuilder,
          evidenceTileBuilder: evidenceTileBuilder,
        );
      case 'disagreement_rebuttal':
        return SeminarSnapshotDisagreementRebuttalTiles(
          parts: [part],
          zh: zh,
          roleLabelBuilder: roleLabelBuilder,
          evidenceTileBuilder: evidenceTileBuilder,
        );
      case 'review_triage':
        return SeminarSnapshotReviewTriagePartTile(
          part: part,
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
          evidenceRefs: showInlineEvidence
              ? part.evidenceRefs
              : const <AiSeminarRunCardEvidenceSnapshot>[],
          zh: zh,
          labelBuilder: reviewTriageLabelBuilder,
          textBuilder: reviewTriageTextBuilder,
          linkedEvidenceLabel: linkedEvidenceLabel,
          missingSourceLabel: missingSourceLabel,
          evidenceSourceActionBuilder: evidenceSourceActionBuilder,
        );
      case 'artifact_actions':
        return SeminarSnapshotArtifactActionsPartTile(
          part: part,
          zh: zh,
          actionChipLabelBuilder: artifactChipLabelBuilder,
          displayTextBuilder: artifactDisplayTextBuilder,
          statusLabelBuilder: artifactStatusLabelBuilder,
          completedAtLabelBuilder: artifactCompletedAtLabelBuilder,
          detailLabelBuilder: artifactDetailLabelBuilder,
          linkedEvidenceLabel: linkedEvidenceLabel,
          missingSourceLabel: missingSourceLabel,
          evidenceSourceActionBuilder: evidenceSourceActionBuilder,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class SeminarSnapshotReviewTriagePartTile extends StatelessWidget {
  const SeminarSnapshotReviewTriagePartTile({
    required this.part,
    required this.agentRunId,
    required this.parentRunId,
    required this.evidenceRefs,
    required this.zh,
    required this.labelBuilder,
    required this.textBuilder,
    required this.linkedEvidenceLabel,
    required this.missingSourceLabel,
    required this.evidenceSourceActionBuilder,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final String? agentRunId;
  final String? parentRunId;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final bool zh;
  final SeminarTimelineReviewLabelBuilder labelBuilder;
  final SeminarTimelineReviewTextBuilder textBuilder;
  final String linkedEvidenceLabel;
  final String missingSourceLabel;
  final SeminarTimelineEvidenceSourceActionBuilder evidenceSourceActionBuilder;

  @override
  Widget build(BuildContext context) {
    return SeminarSnapshotNativeTextPartTile(
      icon: Icons.rule_folder_outlined,
      label: labelBuilder(part.label),
      text: textBuilder(part),
      agentRunId: agentRunId,
      parentRunId: parentRunId,
      evidenceRefs: evidenceRefs,
      zh: zh,
      linkedEvidenceLabel: linkedEvidenceLabel,
      missingSourceLabel: missingSourceLabel,
      evidenceSourceActionBuilder: evidenceSourceActionBuilder,
    );
  }
}

class SeminarSnapshotArtifactActionsPartTile extends StatelessWidget {
  const SeminarSnapshotArtifactActionsPartTile({
    required this.part,
    required this.zh,
    required this.actionChipLabelBuilder,
    required this.displayTextBuilder,
    required this.statusLabelBuilder,
    required this.completedAtLabelBuilder,
    required this.detailLabelBuilder,
    required this.linkedEvidenceLabel,
    required this.missingSourceLabel,
    required this.evidenceSourceActionBuilder,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarTimelineArtifactChipLabelBuilder actionChipLabelBuilder;
  final SeminarTimelineArtifactDisplayTextBuilder displayTextBuilder;
  final SeminarTimelineArtifactStatusLabelBuilder statusLabelBuilder;
  final SeminarTimelineArtifactCompletedAtLabelBuilder completedAtLabelBuilder;
  final SeminarTimelineArtifactDetailLabelBuilder detailLabelBuilder;
  final String linkedEvidenceLabel;
  final String missingSourceLabel;
  final SeminarTimelineEvidenceSourceActionBuilder evidenceSourceActionBuilder;

  @override
  Widget build(BuildContext context) {
    final actionLabels = part.actionIds
        .map(actionChipLabelBuilder)
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final text = displayTextBuilder(part.text?.trim() ?? '');
    final statusLabel = statusLabelBuilder(part.status);
    final completedAtLabel = completedAtLabelBuilder(
      part.status,
      part.completedAt,
    );
    final detailLabel = detailLabelBuilder(part.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            zh ? '沉淀动作' : 'Artifact actions',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (statusLabel != null || completedAtLabel != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (statusLabel != null)
                            SeminarSnapshotTinyChip(statusLabel),
                          if (completedAtLabel != null)
                            SeminarSnapshotTinyChip(completedAtLabel),
                        ],
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: zh,
                    ),
                    SeminarSnapshotCompactEvidenceRows(
                      evidenceRefs: part.evidenceRefs,
                      linkedEvidenceLabel: linkedEvidenceLabel,
                      missingSourceLabel: missingSourceLabel,
                      sourceActionBuilder: evidenceSourceActionBuilder,
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detailLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (actionLabels.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in actionLabels)
                            SeminarSnapshotTinyChip(label),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SeminarSnapshotRunSetupPartTile extends StatelessWidget {
  const SeminarSnapshotRunSetupPartTile({
    required this.part,
    required this.zh,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      part.text?.trim() ?? '',
      part.label?.trim() ?? '',
    ].where((line) => line.isNotEmpty).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.tune_outlined,
              size: 18,
              color: ClaudePalette.accent(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zh ? '本次设置' : 'Run setup',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final line in lines)
                      Text(
                        line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SeminarSnapshotNativeTextPartTile extends StatelessWidget {
  const SeminarSnapshotNativeTextPartTile({
    required this.icon,
    required this.label,
    required this.text,
    required this.zh,
    required this.linkedEvidenceLabel,
    required this.missingSourceLabel,
    required this.evidenceSourceActionBuilder,
    this.contextLabel,
    this.detailChipLabel,
    this.agentRunId,
    this.parentRunId,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
    super.key,
  });

  final IconData icon;
  final String label;
  final String? contextLabel;
  final String text;
  final String? detailChipLabel;
  final String? agentRunId;
  final String? parentRunId;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final bool zh;
  final String linkedEvidenceLabel;
  final String missingSourceLabel;
  final SeminarTimelineEvidenceSourceActionBuilder evidenceSourceActionBuilder;

  @override
  Widget build(BuildContext context) {
    final normalizedText = text.trim();
    final normalizedContextLabel = contextLabel?.trim() ?? '';
    final normalizedDetailChipLabel = detailChipLabel?.trim() ?? '';
    if (normalizedText.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: ClaudePalette.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (normalizedContextLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        normalizedContextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    SeminarSnapshotExpandableText(
                      normalizedText,
                      collapsedMaxLines: 4,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.secondary(context),
                            height: 1.32,
                          ),
                    ),
                    if (normalizedDetailChipLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          SeminarSnapshotTinyChip(
                            normalizedDetailChipLabel,
                          ),
                        ],
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      agentRunId,
                      parentRunId: parentRunId,
                      zh: zh,
                    ),
                    SeminarSnapshotCompactEvidenceRows(
                      evidenceRefs: evidenceRefs,
                      linkedEvidenceLabel: linkedEvidenceLabel,
                      missingSourceLabel: missingSourceLabel,
                      sourceActionBuilder: evidenceSourceActionBuilder,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeminarSnapshotEvidenceBundlePartTile extends StatelessWidget {
  const _SeminarSnapshotEvidenceBundlePartTile({
    required this.part,
    required this.zh,
    required this.evidenceTileBuilder,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarTimelineEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    final evidenceRefs = part.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final label = part.label?.trim().isNotEmpty == true
        ? part.label!.trim()
        : zh
            ? '证据快照'
            : 'Evidence snapshot';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(Icons.fact_check_outlined, label),
        const SizedBox(height: 6),
        for (final evidence in evidenceRefs) evidenceTileBuilder(evidence),
      ],
    );
  }
}
