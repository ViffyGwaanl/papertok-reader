import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';

typedef SeminarParticipationLabelBuilder = String Function(String? value);
typedef SeminarParticipationRoleLabelBuilder = String Function(String roleId);
typedef SeminarParticipationStatusLabelBuilder = String? Function(
  String? status,
);
typedef SeminarParticipationCompletedAtLabelBuilder = String? Function(
  String? status,
  int? completedAt,
);
typedef SeminarParticipationToolLabelBuilder = String Function(String toolId);
typedef SeminarParticipationActionEnabledBuilder = bool Function(
  String actionId,
);
typedef SeminarParticipationActionWidgetBuilder = Widget Function(
  String actionId,
);

String? seminarAgentRunIdFromStatusPart(AiSeminarRunCardMessagePart part) {
  final type = part.type.trim();
  if (type != 'director_state' && type != 'agent_status') return null;
  final agentRunId = part.agentRunId?.trim();
  if (agentRunId != null && agentRunId.isNotEmpty) return agentRunId;
  final id = part.id?.trim();
  if (id == null || id.isEmpty) return null;
  const marker = ':status:';
  final markerIndex = id.lastIndexOf(marker);
  if (markerIndex <= 0) return null;
  return id.substring(0, markerIndex);
}

String seminarAgentControlActionLabel(String? action, {required bool zh}) {
  switch (action?.trim()) {
    case 'wait-agent':
      return zh ? '等待角色' : 'Wait for role';
    case 'wait-tool-call':
      return zh ? '证据检索中…' : 'Retrieving evidence...';
    case 'cancel-tool-call':
      return zh ? '取消工具调用' : 'Cancel tool call';
    case 'send-input':
      return zh ? '发送输入' : 'Send input';
    case 'resume-agent':
      return zh ? '继续角色' : 'Resume role';
    case 'close-agent':
      return zh ? '停止角色' : 'Stop role';
    case 'retry-agent-control':
      return zh ? '重新生成角色' : 'Regenerate role';
    default:
      return '';
  }
}

bool seminarAgentControlActionIsExecutable(
  AiSeminarRunCardMessagePart part, {
  required String actionId,
  required String? sessionId,
}) {
  final normalizedSessionId = sessionId?.trim();
  if (normalizedSessionId?.isNotEmpty != true) return false;
  final agentRunId = seminarAgentRunIdFromStatusPart(part);
  if (agentRunId == null) return false;
  switch (actionId.trim()) {
    case 'wait-agent':
      return _seminarAgentStatusOneOf(
        part,
        const ['role-pending', 'role-running'],
      );
    case 'close-agent':
      return _seminarAgentStatusOneOf(
        part,
        const [
          'role-pending',
          'role-running',
          'role-waiting-input',
          'role-interrupted',
        ],
      );
    case 'send-input':
      return _seminarAgentStatusOneOf(part, const ['role-waiting-input']);
    case 'resume-agent':
      return _seminarAgentStatusOneOf(part, const ['role-interrupted']);
    case 'retry-agent-control':
      return _seminarAgentStatusOneOf(part, const ['role-error', 'failed']);
    default:
      return false;
  }
}

IconData seminarAgentControlActionIcon(String actionId) {
  switch (actionId.trim()) {
    case 'close-agent':
      return Icons.stop_circle_outlined;
    case 'wait-agent':
      return Icons.hourglass_empty_outlined;
    case 'send-input':
      return Icons.send_outlined;
    case 'resume-agent':
      return Icons.restart_alt_outlined;
    case 'retry-agent-control':
      return Icons.replay_outlined;
    default:
      return Icons.tune_outlined;
  }
}

bool _seminarAgentStatusOneOf(
  AiSeminarRunCardMessagePart part,
  List<String> statuses,
) {
  final status = part.label?.trim();
  return status != null && statuses.contains(status);
}

class SeminarSnapshotReaderTurnTile extends StatelessWidget {
  const SeminarSnapshotReaderTurnTile({
    required this.part,
    required this.zh,
    required this.roleLabelBuilder,
    required this.actionLabelBuilder,
    required this.statusLabelBuilder,
    required this.completedAtLabelBuilder,
    required this.toolLabelBuilder,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarParticipationRoleLabelBuilder roleLabelBuilder;
  final SeminarParticipationLabelBuilder actionLabelBuilder;
  final SeminarParticipationStatusLabelBuilder statusLabelBuilder;
  final SeminarParticipationCompletedAtLabelBuilder completedAtLabelBuilder;
  final SeminarParticipationToolLabelBuilder toolLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final targetRole = part.roleId?.trim();
    final action = part.label?.trim();
    final targetLabel = targetRole == null || targetRole.isEmpty
        ? ''
        : roleLabelBuilder(targetRole);
    final actionLabel = actionLabelBuilder(action);
    final statusLabel = statusLabelBuilder(part.status);
    final completedAtLabel = completedAtLabelBuilder(
      part.status,
      part.completedAt,
    );
    final toolId = part.toolId?.trim() ?? '';
    final toolLabel = toolId.isEmpty ? '' : toolLabelBuilder(toolId).trim();
    final query = part.query?.trim() ?? '';
    final meta = [
      if (actionLabel.isNotEmpty) actionLabel,
      if (targetLabel.isNotEmpty) targetLabel,
    ].join(' · ');
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
              Icon(
                Icons.person_outline,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    if (part.text?.trim().isNotEmpty == true) ...[
                      if (meta.isNotEmpty) const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    if (toolLabel.isNotEmpty || query.isNotEmpty) ...[
                      if (meta.isNotEmpty ||
                          part.text?.trim().isNotEmpty == true)
                        const SizedBox(height: 5),
                      if (toolLabel.isNotEmpty)
                        Text(
                          zh ? '工具：$toolLabel' : 'Tool: $toolLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      if (query.isNotEmpty)
                        Text(
                          zh ? '查询：$query' : 'Query: $query',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                    ],
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

class SeminarSnapshotReaderComposerTile extends StatelessWidget {
  const SeminarSnapshotReaderComposerTile({
    required this.part,
    required this.zh,
    required this.roleLabelBuilder,
    required this.actionLabelBuilder,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarParticipationRoleLabelBuilder roleLabelBuilder;
  final SeminarParticipationLabelBuilder actionLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final prompt = part.text?.trim();
    final actionLabels = part.actionIds
        .map(actionLabelBuilder)
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    final roleLabels = part.roleIds
        .map((roleId) => roleLabelBuilder(roleId.trim()))
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    final defaultActionLabel = part.defaultActionId?.trim().isNotEmpty == true
        ? actionLabelBuilder(part.defaultActionId!.trim())
        : null;
    final defaultRoleLabel = part.defaultRoleId?.trim().isNotEmpty == true
        ? roleLabelBuilder(part.defaultRoleId!.trim())
        : null;
    final selectedActionLabel = part.selectedActionId?.trim().isNotEmpty == true
        ? actionLabelBuilder(part.selectedActionId!.trim())
        : null;
    final selectedRoleLabel = part.selectedRoleId?.trim().isNotEmpty == true
        ? roleLabelBuilder(part.selectedRoleId!.trim())
        : null;
    final draftText = part.draftText?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zh
                    ? '这场研讨可继续由读者参与'
                    : 'This Seminar can continue with a reader turn',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: ClaudePalette.fg(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (prompt != null && prompt.isNotEmpty) ...[
                const SizedBox(height: 4),
                SeminarSnapshotExpandableText(
                  prompt,
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
              if (defaultActionLabel != null || defaultRoleLabel != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (defaultActionLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: zh ? '默认动作' : 'Default action',
                        value: defaultActionLabel,
                      ),
                    if (defaultRoleLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: zh ? '默认角色' : 'Default role',
                        value: defaultRoleLabel,
                      ),
                  ],
                ),
              ],
              if (selectedActionLabel != null || selectedRoleLabel != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (selectedActionLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: zh ? '当前动作' : 'Current action',
                        value: selectedActionLabel,
                      ),
                    if (selectedRoleLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: zh ? '当前角色' : 'Current role',
                        value: selectedRoleLabel,
                      ),
                  ],
                ),
              ],
              if (draftText != null && draftText.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(zh ? '草稿回复' : 'Draft reply'),
                const SizedBox(height: 4),
                SeminarSnapshotExpandableText(
                  draftText,
                  collapsedMaxLines: 4,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              if (actionLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(zh ? '可用动作' : 'Available actions'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in actionLabels)
                      SeminarSnapshotTinyChip(label),
                  ],
                ),
              ],
              if (roleLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(zh ? '可用角色' : 'Available roles'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in roleLabels)
                      SeminarSnapshotTinyChip(label),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SeminarSnapshotDirectorCueTile extends StatelessWidget {
  const SeminarSnapshotDirectorCueTile({
    required this.part,
    required this.zh,
    required this.directorCueLabelBuilder,
    required this.actionLabelBuilder,
    required this.actionEnabledBuilder,
    required this.actionWidgetBuilder,
    this.agentInputComposer,
    super.key,
  });

  final AiSeminarRunCardMessagePart part;
  final bool zh;
  final SeminarParticipationLabelBuilder directorCueLabelBuilder;
  final SeminarParticipationLabelBuilder actionLabelBuilder;
  final SeminarParticipationActionEnabledBuilder actionEnabledBuilder;
  final SeminarParticipationActionWidgetBuilder actionWidgetBuilder;
  final Widget? agentInputComposer;

  @override
  Widget build(BuildContext context) {
    final intent = part.label?.trim();
    final cueText = part.text?.trim();
    final controlActionIds = part.actionIds
        .map((actionId) => actionId.trim())
        .where((actionId) => actionLabelBuilder(actionId).isNotEmpty)
        .toList(growable: false);
    final inlineControlActionIds = controlActionIds
        .where((actionId) => !actionEnabledBuilder(actionId))
        .toList(growable: false);
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
                Icons.psychology_outlined,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      directorCueLabelBuilder(intent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (cueText != null && cueText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        cueText,
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
                    if (inlineControlActionIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(
                        zh ? '历史控制' : 'Recorded controls',
                      ),
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

class SeminarAgentControlAction extends StatelessWidget {
  const SeminarAgentControlAction({
    required this.actionId,
    required this.agentRunId,
    required this.label,
    required this.icon,
    required this.isExecutable,
    required this.isSubmitting,
    required this.onPressed,
    super.key,
  });

  final String actionId;
  final String agentRunId;
  final String label;
  final IconData icon;
  final bool isExecutable;
  final bool isSubmitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    if (!isExecutable) return SeminarSnapshotTinyChip(label);
    return ActionChip(
      key: ValueKey(
        'seminar-chat-card-agent-action-$actionId-$agentRunId',
      ),
      avatar: Icon(
        icon,
        size: 16,
        color: isSubmitting
            ? ClaudePalette.secondary(context)
            : ClaudePalette.accent(context),
      ),
      label: Text(label),
      onPressed: isSubmitting ? null : onPressed,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ClaudePalette.fg(context),
            fontWeight: FontWeight.w700,
          ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          Theme.of(context).colorScheme.secondaryContainer.withValues(
                alpha: 0.72,
              ),
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class SeminarAgentInputComposer extends StatelessWidget {
  const SeminarAgentInputComposer({
    required this.agentRunId,
    required this.controller,
    required this.zh,
    required this.isSubmitting,
    required this.onChanged,
    required this.onSubmit,
    super.key,
  });

  final String agentRunId;
  final TextEditingController controller;
  final bool zh;
  final bool isSubmitting;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('seminar-chat-card-agent-input-$agentRunId'),
            controller: controller,
            minLines: 1,
            maxLines: 3,
            enabled: !isSubmitting,
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              labelText: zh ? '输入给角色' : 'Input for role',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: ValueKey('seminar-chat-card-agent-input-submit-$agentRunId'),
          tooltip: zh ? '发送输入' : 'Send input',
          onPressed: isSubmitting || !hasText ? null : onSubmit,
          icon: const Icon(Icons.send_outlined, size: 18),
        ),
      ],
    );
  }
}
