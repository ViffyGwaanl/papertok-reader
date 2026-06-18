import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/participation/seminar_participation_widgets.dart';

typedef SeminarRunRoleLabelBuilder = String Function(AiSeminarRole role);
typedef SeminarRunEvidenceScopeLabelBuilder = String Function(
  AiSeminarEvidenceScope scope,
);
typedef SeminarRunToolLabelBuilder = String Function(String toolId);
typedef SeminarRunActionWidgetBuilder = Widget Function(
  AiSeminarRunCardMessagePart part,
  String actionId,
);

class SeminarRunCardSetup extends StatelessWidget {
  const SeminarRunCardSetup({
    required this.card,
    required this.zh,
    required this.isExpanded,
    required this.evidenceSummary,
    required this.toolSummary,
    required this.roleSummary,
    required this.roles,
    required this.evidenceScopeOptions,
    required this.toolIds,
    required this.roleLabelBuilder,
    required this.evidenceScopeLabelBuilder,
    required this.toolLabelBuilder,
    required this.questionController,
    required this.rolePromptControllerBuilder,
    required this.roleEvidenceScopesBuilder,
    required this.roleAllowedToolIdsBuilder,
    required this.onToggleExpanded,
    required this.onQuestionChanged,
    required this.onToggleRole,
    required this.onRolePromptChanged,
    required this.onToggleRoleEvidenceScope,
    required this.onToggleRoleTool,
    required this.onMaxRoundsChanged,
    super.key,
  });

  final AiSeminarRunCardMeta card;
  final bool zh;
  final bool isExpanded;
  final String evidenceSummary;
  final String toolSummary;
  final String roleSummary;
  final List<AiSeminarRole> roles;
  final List<AiSeminarEvidenceScope> evidenceScopeOptions;
  final List<String> toolIds;
  final SeminarRunRoleLabelBuilder roleLabelBuilder;
  final SeminarRunEvidenceScopeLabelBuilder evidenceScopeLabelBuilder;
  final SeminarRunToolLabelBuilder toolLabelBuilder;
  final TextEditingController? questionController;
  final TextEditingController Function(AiSeminarRole role)
      rolePromptControllerBuilder;
  final Set<AiSeminarEvidenceScope> Function(AiSeminarRole role)
      roleEvidenceScopesBuilder;
  final Set<String> Function(AiSeminarRole role) roleAllowedToolIdsBuilder;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onQuestionChanged;
  final ValueChanged<AiSeminarRole> onToggleRole;
  final void Function(AiSeminarRole role, String value) onRolePromptChanged;
  final void Function(AiSeminarRole role, AiSeminarEvidenceScope scope)
      onToggleRoleEvidenceScope;
  final void Function(AiSeminarRole role, String toolId) onToggleRoleTool;
  final ValueChanged<int> onMaxRoundsChanged;

  @override
  Widget build(BuildContext context) {
    final sessionId = card.sessionId?.trim();
    final expandedSessionId = isExpanded ? sessionId : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        _localized(
                          zh: zh,
                          zhText: '本次设置',
                          en: 'Run setup',
                        ),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ClaudePalette.fg(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$roleSummary · $evidenceSummary · $toolSummary',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                if (sessionId != null && sessionId.isNotEmpty)
                  TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(
                      _localized(
                        zh: zh,
                        zhText: isExpanded ? '收起设置' : '调整设置',
                        en: isExpanded ? 'Hide setup' : 'Adjust setup',
                      ),
                    ),
                  ),
              ],
            ),
            if (expandedSessionId != null && questionController != null) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: ClaudePalette.divider(context)),
              const SizedBox(height: 8),
              SeminarRunCardQuestionField(
                sessionId: expandedSessionId,
                controller: questionController!,
                zh: zh,
                onChanged: onQuestionChanged,
              ),
              const SizedBox(height: 8),
              for (final role in roles) ...[
                SwitchListTile(
                  key: ValueKey(
                    'seminar-chat-card-role-${role.asString}-$expandedSessionId',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: Icon(
                    role == AiSeminarRole.verifier
                        ? Icons.verified_outlined
                        : Icons.record_voice_over_outlined,
                    size: 18,
                  ),
                  title: Text(roleLabelBuilder(role)),
                  subtitle: Text(
                    _localized(
                      zh: zh,
                      zhText: '只影响这场研讨',
                      en: 'Only this seminar run',
                    ),
                  ),
                  value: card.roleIds.contains(role.asString),
                  onChanged: (_) => onToggleRole(role),
                ),
                if (card.roleIds.contains(role.asString))
                  SeminarRunCardRolePromptField(
                    role: role,
                    sessionId: expandedSessionId,
                    controller: rolePromptControllerBuilder(role),
                    label: roleLabelBuilder(role),
                    zh: zh,
                    onChanged: (value) => onRolePromptChanged(role, value),
                  ),
                if (card.roleIds.contains(role.asString))
                  SeminarRunCardRoleEvidenceScopeRow(
                    role: role,
                    sessionId: expandedSessionId,
                    evidenceScopeOptions: evidenceScopeOptions,
                    selectedScopes: roleEvidenceScopesBuilder(role),
                    evidenceScopeLabelBuilder: evidenceScopeLabelBuilder,
                    onToggleScope: (scope) => onToggleRoleEvidenceScope(
                      role,
                      scope,
                    ),
                  ),
                if (card.roleIds.contains(role.asString))
                  SeminarRunCardRoleToolRow(
                    role: role,
                    sessionId: expandedSessionId,
                    toolIds: toolIds,
                    selectedToolIds: roleAllowedToolIdsBuilder(role),
                    toolLabelBuilder: toolLabelBuilder,
                    zh: zh,
                    onToggleTool: (toolId) => onToggleRoleTool(role, toolId),
                  ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _localized(
                        zh: zh,
                        zhText: '最多讨论轮次',
                        en: 'Max discussion rounds',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'seminar-chat-card-rounds-minus-$expandedSessionId',
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _localized(
                      zh: zh,
                      zhText: '减少轮次',
                      en: 'Decrease rounds',
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: card.maxRounds <= 1
                        ? null
                        : () => onMaxRoundsChanged(card.maxRounds - 1),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${card.maxRounds}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'seminar-chat-card-rounds-plus-$expandedSessionId',
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _localized(
                      zh: zh,
                      zhText: '增加轮次',
                      en: 'Increase rounds',
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: card.maxRounds >= 10
                        ? null
                        : () => onMaxRoundsChanged(card.maxRounds + 1),
                  ),
                ],
              ),
              Text(
                _localized(
                  zh: zh,
                  zhText: '只影响本次研讨，不会写回全局 Settings。',
                  en: 'Only this Seminar run changes. Global settings stay unchanged.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SeminarRunCardQuestionField extends StatelessWidget {
  const SeminarRunCardQuestionField({
    required this.sessionId,
    required this.controller,
    required this.zh,
    required this.onChanged,
    super.key,
  });

  final String sessionId;
  final TextEditingController controller;
  final bool zh;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey('seminar-chat-card-question-input-$sessionId'),
      controller: controller,
      minLines: 2,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        isDense: true,
        labelText: _localized(
          zh: zh,
          zhText: '本次研讨问题',
          en: 'Seminar question',
        ),
        hintText: _localized(
          zh: zh,
          zhText: '只影响本次研讨，不写回全局 Settings。',
          en: 'Only this Seminar run changes. Global settings stay unchanged.',
        ),
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

class SeminarRunCardRolePromptField extends StatelessWidget {
  const SeminarRunCardRolePromptField({
    required this.role,
    required this.sessionId,
    required this.controller,
    required this.label,
    required this.zh,
    required this.onChanged,
    super.key,
  });

  final AiSeminarRole role;
  final String sessionId;
  final TextEditingController controller;
  final String label;
  final bool zh;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 8),
      child: TextField(
        key: ValueKey(
          'seminar-chat-card-role-${role.asString}-prompt-$sessionId',
        ),
        controller: controller,
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          isDense: true,
          labelText: _localized(
            zh: zh,
            zhText: '$label本次提示词',
            en: '$label run prompt',
          ),
          hintText: _localized(
            zh: zh,
            zhText: '只影响这场研讨，不写回全局 Settings。',
            en: 'Only this seminar run. Global settings stay unchanged.',
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class SeminarRunCardRoleEvidenceScopeRow extends StatelessWidget {
  const SeminarRunCardRoleEvidenceScopeRow({
    required this.role,
    required this.sessionId,
    required this.evidenceScopeOptions,
    required this.selectedScopes,
    required this.evidenceScopeLabelBuilder,
    required this.onToggleScope,
    super.key,
  });

  final AiSeminarRole role;
  final String sessionId;
  final List<AiSeminarEvidenceScope> evidenceScopeOptions;
  final Set<AiSeminarEvidenceScope> selectedScopes;
  final SeminarRunEvidenceScopeLabelBuilder evidenceScopeLabelBuilder;
  final ValueChanged<AiSeminarEvidenceScope> onToggleScope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scope in evidenceScopeOptions)
            SeminarRunEvidenceScopeChip(
              key: ValueKey(
                'seminar-chat-card-role-${role.asString}-scope-'
                '${scope.asString}-$sessionId',
              ),
              label: evidenceScopeLabelBuilder(scope),
              selected: selectedScopes.contains(scope),
              onPressed: () => onToggleScope(scope),
            ),
        ],
      ),
    );
  }
}

class SeminarRunCardRoleToolRow extends StatelessWidget {
  const SeminarRunCardRoleToolRow({
    required this.role,
    required this.sessionId,
    required this.toolIds,
    required this.selectedToolIds,
    required this.toolLabelBuilder,
    required this.zh,
    required this.onToggleTool,
    super.key,
  });

  final AiSeminarRole role;
  final String sessionId;
  final List<String> toolIds;
  final Set<String> selectedToolIds;
  final SeminarRunToolLabelBuilder toolLabelBuilder;
  final bool zh;
  final ValueChanged<String> onToggleTool;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localized(
              zh: zh,
              zhText: '本次只读工具',
              en: 'Run read-only tools',
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ClaudePalette.fg(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final toolId in toolIds)
                SeminarRunEvidenceScopeChip(
                  key: ValueKey(
                    'seminar-chat-card-role-${role.asString}-tool-'
                    '$toolId-$sessionId',
                  ),
                  label: toolLabelBuilder(toolId),
                  selected: selectedToolIds.contains(toolId),
                  onPressed: () => onToggleTool(toolId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SeminarRunCardStartAction extends StatelessWidget {
  const SeminarRunCardStartAction({
    required this.sessionId,
    required this.isSubmitting,
    required this.zh,
    required this.onStart,
    super.key,
  });

  final String? sessionId;
  final bool isSubmitting;
  final bool zh;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        key: sessionId == null
            ? null
            : ValueKey('seminar-chat-card-start-$sessionId'),
        icon: isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_outlined, size: 18),
        label: Text(
          _localized(
            zh: zh,
            zhText: '开始研讨',
            en: 'Start Seminar',
          ),
        ),
        onPressed: isSubmitting ? null : onStart,
      ),
    );
  }
}

class SeminarRunCardCancelAction extends StatelessWidget {
  const SeminarRunCardCancelAction({
    required this.sessionId,
    required this.zh,
    required this.onCancel,
    super.key,
  });

  final String? sessionId;
  final bool zh;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    return ActionChip(
      key: ValueKey('seminar-chat-card-cancel-$normalizedSessionId'),
      avatar: const Icon(Icons.stop_circle_outlined, size: 16),
      label: Text(
        _localized(
          zh: zh,
          zhText: '取消研讨',
          en: 'Cancel seminar',
        ),
      ),
      onPressed: onCancel,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class SeminarRunEvidenceScopeChip extends StatelessWidget {
  const SeminarRunEvidenceScopeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(
        selected ? Icons.check_circle_outline : Icons.circle_outlined,
        size: 16,
      ),
      onSelected: (_) => onPressed(),
    );
  }
}

List<AiSeminarRole> seminarCardSetupRoles(AiSeminarRunCardMeta card) {
  const order = <AiSeminarRole>[
    AiSeminarRole.critical,
    AiSeminarRole.supportive,
    AiSeminarRole.verifier,
    AiSeminarRole.synthesizer,
  ];
  final seen = <AiSeminarRole>{};
  final roles = <AiSeminarRole>[];
  for (final role in order) {
    if (seen.add(role)) roles.add(role);
  }
  for (final roleId in card.roleIds) {
    final role = AiSeminarRole.fromString(roleId);
    if (role != null && seen.add(role)) roles.add(role);
  }
  return roles;
}

List<Widget> seminarRunCardHeaderControls({
  required String? sessionId,
  required AiSeminarRunCardSnapshot? snapshot,
  required bool canCancelFromCard,
  required bool zh,
  required Widget Function() cancelActionBuilder,
  required SeminarRunActionWidgetBuilder actionWidgetBuilder,
}) {
  final normalizedSessionId = sessionId?.trim();
  if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
    return const [];
  }
  final controls = <Widget>[
    if (canCancelFromCard) cancelActionBuilder(),
  ];
  if (snapshot != null) {
    for (final part in snapshot.messageParts) {
      final actionIds = part.actionIds
          .map((actionId) => actionId.trim())
          .where((actionId) => seminarAgentControlActionLabel(
                actionId,
                zh: zh,
              ).isNotEmpty)
          .where((actionId) => seminarAgentControlActionIsExecutable(
                part,
                actionId: actionId,
                sessionId: normalizedSessionId,
              ))
          .toList(growable: false);
      for (final actionId in actionIds) {
        controls.add(actionWidgetBuilder(part, actionId));
      }
    }
  }
  return controls;
}

String _localized({
  required bool zh,
  required String zhText,
  required String en,
}) {
  return zh ? zhText : en;
}
