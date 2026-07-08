import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/evidence/seminar_evidence_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';

typedef SeminarRoleLabelBuilder = String Function(String roleId);
typedef SeminarRoleIconBuilder = IconData Function(String roleId);
typedef SeminarAgentStatusLabelBuilder = String Function(String? status);
typedef SeminarAgentActionLabelBuilder = String Function(String? actionId);
typedef SeminarAgentActionEnabledBuilder = bool Function(
  String actionId,
);
typedef SeminarAgentActionWidgetBuilder = Widget Function(String actionId);
typedef SeminarAllowedToolIdsBuilder = List<String> Function(
  List<String> toolIds,
);
typedef SeminarToolLabelBuilder = String Function(String toolId);
typedef SeminarIndexedEvidenceTileBuilder = Widget Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
  int fallbackIndex,
);

class SeminarSnapshotRoleTile extends StatelessWidget {
  const SeminarSnapshotRoleTile({
    required this.role,
    required this.label,
    required this.icon,
    required this.zh,
    required this.onEvidencePressed,
    super.key,
  });

  final AiSeminarRunCardRoleSummary role;
  final String label;
  final IconData icon;
  final bool zh;
  final ValueChanged<AiSeminarRunCardEvidenceSnapshot> onEvidencePressed;

  @override
  Widget build(BuildContext context) {
    final summary = role.summary.trim();
    final evidenceRefs = role.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ClaudePalette.accent(context)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ClaudePalette.fg(context),
                      ),
                ),
                if (summary.isNotEmpty)
                  SeminarSnapshotExpandableText(
                    summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.32,
                        ),
                  ),
                if (evidenceRefs.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  SeminarEvidenceReferenceChips(
                    evidenceRefs: evidenceRefs,
                    zh: zh,
                    onEvidencePressed: onEvidencePressed,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SeminarSnapshotDiscussionTimeline extends StatelessWidget {
  const SeminarSnapshotDiscussionTimeline({
    required this.roles,
    required this.rolePartials,
    required this.liveRole,
    required this.liveRoleText,
    required this.zh,
    required this.roleLabelBuilder,
    required this.roleIconBuilder,
    required this.onEvidencePressed,
    required this.evidenceTileBuilder,
    super.key,
  });

  final List<AiSeminarRunCardRoleSummary> roles;
  final List<AiSeminarRunCardRoleSummary> rolePartials;
  final AiSeminarRole? liveRole;
  final String liveRoleText;
  final bool zh;
  final SeminarRoleLabelBuilder roleLabelBuilder;
  final SeminarRoleIconBuilder roleIconBuilder;
  final ValueChanged<AiSeminarRunCardEvidenceSnapshot> onEvidencePressed;
  final SeminarIndexedEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    final turns = roles.where((role) => !role.isEmpty).toList();
    final partials = rolePartials.where((role) => !role.isEmpty).toList();
    final normalizedLiveText = liveRoleText.trim();
    final hasLiveRole = liveRole != null && normalizedLiveText.isNotEmpty;
    if (turns.isEmpty && partials.isEmpty && !hasLiveRole) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.chat_bubble_outline,
          zh ? '研讨时间线' : 'Discussion timeline',
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < turns.length; index += 1)
          SeminarSnapshotTimelineTurn(
            role: turns[index],
            turnNumber: index + 1,
            label: _roleLabel(turns[index]),
            icon: roleIconBuilder(turns[index].roleId),
            zh: zh,
            onEvidencePressed: onEvidencePressed,
            evidenceTileBuilder: evidenceTileBuilder,
          ),
        for (final partial in partials)
          SeminarSnapshotRolePartialTile(
            partial: partial,
            label: _roleLabel(partial),
            icon: roleIconBuilder(partial.roleId),
            zh: zh,
          ),
        if (hasLiveRole)
          SeminarSnapshotLiveRoleTile(
            label: roleLabelBuilder(liveRole!.asString),
            icon: roleIconBuilder(liveRole!.asString),
            partialText: normalizedLiveText,
            zh: zh,
          ),
      ],
    );
  }

  String _roleLabel(AiSeminarRunCardRoleSummary role) =>
      role.label.trim().isNotEmpty
          ? role.label.trim()
          : roleLabelBuilder(role.roleId.trim());
}

class SeminarSnapshotRolePartialTile extends StatelessWidget {
  const SeminarSnapshotRolePartialTile({
    required this.partial,
    required this.label,
    required this.icon,
    required this.zh,
    super.key,
  });

  final AiSeminarRunCardRoleSummary partial;
  final String label;
  final IconData icon;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return _SeminarStreamingRoleTile(
      label: label,
      icon: icon,
      text: partial.summary.trim(),
      zh: zh,
    );
  }
}

class SeminarSnapshotLiveRoleTile extends StatelessWidget {
  const SeminarSnapshotLiveRoleTile({
    required this.label,
    required this.icon,
    required this.partialText,
    required this.zh,
    super.key,
  });

  final String label;
  final IconData icon;
  final String partialText;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return _SeminarStreamingRoleTile(
      label: label,
      icon: icon,
      text: partialText.trim(),
      zh: zh,
    );
  }
}

class _SeminarStreamingRoleTile extends StatelessWidget {
  const _SeminarStreamingRoleTile({
    required this.label,
    required this.icon,
    required this.text,
    required this.zh,
  });

  final String label;
  final IconData icon;
  final String text;
  final bool zh;

  @override
  Widget build(BuildContext context) {
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
                      zh ? '角色发言生成中' : 'Role turn streaming',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.secondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        text,
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
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

class SeminarSnapshotTimelineTurn extends StatelessWidget {
  const SeminarSnapshotTimelineTurn({
    required this.role,
    required this.turnNumber,
    required this.label,
    required this.icon,
    required this.zh,
    required this.onEvidencePressed,
    required this.evidenceTileBuilder,
    this.agentRunId,
    this.parentRunId,
    super.key,
  });

  final AiSeminarRunCardRoleSummary role;
  final int turnNumber;
  final String label;
  final IconData icon;
  final bool zh;
  final ValueChanged<AiSeminarRunCardEvidenceSnapshot> onEvidencePressed;
  final SeminarIndexedEvidenceTileBuilder evidenceTileBuilder;
  final String? agentRunId;
  final String? parentRunId;

  @override
  Widget build(BuildContext context) {
    final evidenceRefs = role.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
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
                      '$turnNumber · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (role.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        role.summary.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      agentRunId,
                      parentRunId: parentRunId,
                      zh: zh,
                    ),
                    if (evidenceRefs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SeminarEvidenceReferenceChips(
                        evidenceRefs: evidenceRefs,
                        zh: zh,
                        onEvidencePressed: onEvidencePressed,
                      ),
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        zh ? '本轮证据' : 'Evidence used by this turn',
                      ),
                      const SizedBox(height: 5),
                      for (var index = 0; index < evidenceRefs.length; index++)
                        evidenceTileBuilder(evidenceRefs[index], index + 1),
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

class SeminarSnapshotAgentStatusTile extends StatelessWidget {
  const SeminarSnapshotAgentStatusTile({
    required this.part,
    required this.zh,
    required this.statusLabelBuilder,
    required this.roleLabelBuilder,
    required this.actionLabelBuilder,
    required this.actionEnabledBuilder,
    required this.actionWidgetBuilder,
    required this.allowedToolIdsBuilder,
    required this.toolLabelBuilder,
    this.agentInputComposer,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarAgentStatusLabelBuilder statusLabelBuilder;
  final SeminarRoleLabelBuilder roleLabelBuilder;
  final SeminarAgentActionLabelBuilder actionLabelBuilder;
  final SeminarAgentActionEnabledBuilder actionEnabledBuilder;
  final SeminarAgentActionWidgetBuilder actionWidgetBuilder;
  final SeminarAllowedToolIdsBuilder allowedToolIdsBuilder;
  final SeminarToolLabelBuilder toolLabelBuilder;
  final Widget? agentInputComposer;

  @override
  Widget build(BuildContext context) {
    final status = part.label?.trim();
    final statusText = part.text?.trim();
    final roleId = part.roleId?.trim();
    final controlActionIds = part.actionIds
        .map((actionId) => actionId.trim())
        .where((actionId) => actionLabelBuilder(actionId).isNotEmpty)
        .toList(growable: false);
    final inlineControlActionIds = controlActionIds
        .where((actionId) => !actionEnabledBuilder(actionId))
        .toList(growable: false);
    final allowedToolIds = allowedToolIdsBuilder(part.allowedToolIds);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.support_agent_outlined,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeminarSnapshotLabelText(zh ? '角色状态' : 'Role status'),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          statusLabelBuilder(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: ClaudePalette.fg(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (roleId != null && roleId.isNotEmpty)
                          SeminarSnapshotTinyChip(roleLabelBuilder(roleId)),
                      ],
                    ),
                    if (statusText != null && statusText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        statusText,
                        collapsedMaxLines: 3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: zh,
                    ),
                    if (allowedToolIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(zh ? '允许工具' : 'Allowed tools'),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final toolId in allowedToolIds)
                            SeminarSnapshotTinyChip(toolLabelBuilder(toolId)),
                        ],
                      ),
                    ],
                    if (inlineControlActionIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(
                          zh ? '历史控制' : 'Recorded controls'),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final actionId in inlineControlActionIds)
                            actionWidgetBuilder(actionId),
                        ],
                      ),
                    ],
                    if (agentInputComposer != null) ...[
                      const SizedBox(height: 8),
                      agentInputComposer!,
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
