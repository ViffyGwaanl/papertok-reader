import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_run_trace_label.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';

typedef SeminarToolCallActionLabelBuilder = String Function(String? actionId);
typedef SeminarToolCallActionIconBuilder = IconData Function(String actionId);
typedef SeminarToolCallActionEnabledBuilder = bool Function(String actionId);
typedef SeminarToolCallActionPressedBuilder = VoidCallback? Function(
  String actionId,
);
typedef SeminarEvidenceTileBuilder = Widget Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);

class SeminarSnapshotAgentTraceRows extends StatelessWidget {
  const SeminarSnapshotAgentTraceRows(
    this.agentRunId, {
    required this.zh,
    this.parentRunId,
    super.key,
  });

  final String? agentRunId;
  final String? parentRunId;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final normalizedRunId = agentRunId?.trim();
    final normalizedParentRunId = parentRunId?.trim();
    final hasAgentRunId = normalizedRunId != null && normalizedRunId.isNotEmpty;
    final hasParentRunId =
        normalizedParentRunId != null && normalizedParentRunId.isNotEmpty;
    if (!hasAgentRunId && !hasParentRunId) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        SeminarSnapshotDetailLabel(zh ? '运行追踪' : 'Agent trace'),
        if (hasAgentRunId) ...[
          const SizedBox(height: 4),
          Text(
            seminarRunTraceLabel(normalizedRunId, zh: zh),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                  height: 1.32,
                ),
          ),
        ],
        if (hasParentRunId) ...[
          const SizedBox(height: 4),
          SeminarSnapshotDetailLabel(zh ? '父运行' : 'Parent run'),
          const SizedBox(height: 3),
          Text(
            seminarRunTraceLabel(normalizedParentRunId, zh: zh),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                  height: 1.32,
                ),
          ),
        ],
      ],
    );
  }
}

class SeminarSnapshotToolCallTile extends StatelessWidget {
  const SeminarSnapshotToolCallTile({
    required this.toolCall,
    required this.label,
    required this.statusLabel,
    required this.startedAtLabel,
    required this.completedAtLabel,
    required this.durationLabel,
    required this.visibleRoleLabels,
    required this.outputLabel,
    required this.zh,
    required this.actionLabelBuilder,
    required this.actionIconBuilder,
    required this.actionEnabledBuilder,
    required this.actionPressedBuilder,
    required this.evidenceTileBuilder,
    this.isSubmitting = false,
    super.key,
  });

  final AiSeminarRunCardToolCallSnapshot toolCall;
  final String label;
  final String? statusLabel;
  final String? startedAtLabel;
  final String? completedAtLabel;
  final String? durationLabel;
  final String visibleRoleLabels;
  final String outputLabel;
  final bool zh;
  final SeminarToolCallActionLabelBuilder actionLabelBuilder;
  final SeminarToolCallActionIconBuilder actionIconBuilder;
  final SeminarToolCallActionEnabledBuilder actionEnabledBuilder;
  final SeminarToolCallActionPressedBuilder actionPressedBuilder;
  final SeminarEvidenceTileBuilder evidenceTileBuilder;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final query = toolCall.query.trim();
    final evidenceRefs = toolCall.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final outputText = toolCall.text?.trim() ?? '';
    final actionIds = toolCall.actionIds
        .map((actionId) => actionId.trim())
        .where((actionId) => actionLabelBuilder(actionId).isNotEmpty)
        .toList(growable: false);
    final hasExecutableAction = actionIds.any(actionEnabledBuilder);
    final agentRunId = toolCall.agentRunId?.trim();
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SeminarToolCallHeader(
                label: label,
                statusLabel: statusLabel,
                startedAtLabel: startedAtLabel,
                completedAtLabel: completedAtLabel,
                durationLabel: durationLabel,
                resultCount: toolCall.resultCount,
                resultCountLabel: _toolCallResultCountLabel(
                  toolCall.resultCount,
                ),
              ),
              if (query.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  zh ? '查询：$query' : 'Query: $query',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              if (visibleRoleLabels.isNotEmpty) ...[
                const SizedBox(height: 6),
                SeminarSnapshotDetailLabel(zh ? '可见角色' : 'Visible roles'),
                const SizedBox(height: 4),
                Text(
                  visibleRoleLabels,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              if (outputText.isNotEmpty) ...[
                const SizedBox(height: 6),
                SeminarSnapshotDetailLabel(outputLabel),
                const SizedBox(height: 4),
                SeminarSnapshotExpandableText(
                  outputText,
                  collapsedMaxLines: 3,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              SeminarSnapshotAgentTraceRows(
                agentRunId,
                parentRunId: toolCall.parentRunId,
                zh: zh,
              ),
              if (actionIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotDetailLabel(
                  hasExecutableAction
                      ? (zh ? '可用控制' : 'Available controls')
                      : (zh ? '历史控制' : 'Recorded controls'),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final actionId in actionIds)
                      SeminarToolCallAction(
                        actionId: actionId,
                        label: actionLabelBuilder(actionId),
                        icon: actionIconBuilder(actionId),
                        isExecutable: actionEnabledBuilder(actionId),
                        isSubmitting: isSubmitting,
                        toolCallId: toolCall.id,
                        agentRunId: toolCall.agentRunId,
                        onPressed: actionPressedBuilder(actionId),
                      ),
                  ],
                ),
              ],
              if (evidenceRefs.isNotEmpty) ...[
                const SizedBox(height: 7),
                SeminarSnapshotDetailLabel(
                  zh ? '返回证据' : 'Returned evidence',
                ),
                const SizedBox(height: 5),
                for (final evidence in evidenceRefs)
                  evidenceTileBuilder(evidence),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _toolCallResultCountLabel(int count) {
    if (zh) return '$count 个结果';
    return count == 1 ? '1 result' : '$count results';
  }
}

class _SeminarToolCallHeader extends StatelessWidget {
  const _SeminarToolCallHeader({
    required this.label,
    required this.statusLabel,
    required this.startedAtLabel,
    required this.completedAtLabel,
    required this.durationLabel,
    required this.resultCount,
    required this.resultCountLabel,
  });

  final String label;
  final String? statusLabel;
  final String? startedAtLabel;
  final String? completedAtLabel;
  final String? durationLabel;
  final int resultCount;
  final String resultCountLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.search_outlined,
          size: 16,
          color: ClaudePalette.accent(context),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ClaudePalette.fg(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (statusLabel != null ||
            startedAtLabel != null ||
            completedAtLabel != null ||
            durationLabel != null ||
            resultCount > 0) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (statusLabel != null)
                  SeminarSnapshotTinyChip(statusLabel!)
                else if (resultCount > 0)
                  SeminarSnapshotTinyChip(resultCountLabel),
                if (startedAtLabel != null)
                  SeminarSnapshotTinyChip(startedAtLabel!),
                if (completedAtLabel != null)
                  SeminarSnapshotTinyChip(completedAtLabel!),
                if (durationLabel != null)
                  SeminarSnapshotTinyChip(durationLabel!),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SeminarToolCallAction extends StatelessWidget {
  const SeminarToolCallAction({
    required this.actionId,
    required this.label,
    required this.icon,
    required this.isExecutable,
    required this.isSubmitting,
    required this.toolCallId,
    required this.agentRunId,
    required this.onPressed,
    super.key,
  });

  final String actionId;
  final String label;
  final IconData icon;
  final bool isExecutable;
  final bool isSubmitting;
  final String? toolCallId;
  final String? agentRunId;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    if (!isExecutable) return SeminarSnapshotTinyChip(label);
    final normalizedToolCallId = toolCallId?.trim();
    final normalizedAgentRunId = agentRunId?.trim();
    return ActionChip(
      key: ValueKey(
        'seminar-chat-card-tool-action-$actionId-'
        '${normalizedToolCallId?.isNotEmpty == true ? normalizedToolCallId : normalizedAgentRunId}',
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
