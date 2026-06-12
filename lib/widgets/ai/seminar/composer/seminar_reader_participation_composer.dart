import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/composer/seminar_reader_composer_policy.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_expandable_text.dart';

typedef SeminarRoleLabelBuilder = String Function(String roleId);

class SeminarReaderParticipationComposer extends StatelessWidget {
  const SeminarReaderParticipationComposer({
    super.key,
    required this.sessionId,
    required this.controller,
    required this.roles,
    required this.selectedRole,
    required this.activeIntentId,
    required this.isSubmitting,
    required this.isAwaitingReader,
    required this.showHint,
    required this.roleLabelBuilder,
    required this.onQuickAction,
    required this.onSend,
    required this.onRoleChanged,
    required this.onDraftChanged,
    required this.onDismissHint,
    this.askUserQuestion,
  });

  final String sessionId;
  final TextEditingController controller;
  final List<AiSeminarRole> roles;
  final AiSeminarRole? selectedRole;
  final String? activeIntentId;
  final bool isSubmitting;
  final bool isAwaitingReader;
  final bool showHint;
  final String? askUserQuestion;
  final SeminarRoleLabelBuilder roleLabelBuilder;
  final ValueChanged<SeminarParticipationQuickAction> onQuickAction;
  final VoidCallback onSend;
  final ValueChanged<AiSeminarRole?> onRoleChanged;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onDismissHint;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final canSend = !isSubmitting && controller.text.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.36),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.aiSeminarParticipationTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: ClaudePalette.fg(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (showHint) ...[
              const SizedBox(height: 8),
              _DismissibleHint(onDismiss: onDismissHint),
            ],
            if (isAwaitingReader || askUserQuestion?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  askUserQuestion?.trim().isNotEmpty == true
                      ? askUserQuestion!.trim()
                      : l10n.aiSeminarParticipationAwaitingReader,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickActionChip(
                  sessionId: sessionId,
                  action: SeminarParticipationQuickAction.continueDiscussion,
                  activeIntentId: activeIntentId,
                  isSubmitting: isSubmitting,
                  label: l10n.aiSeminarParticipationContinue,
                  icon: Icons.forum_outlined,
                  onPressed: onQuickAction,
                ),
                _QuickActionChip(
                  sessionId: sessionId,
                  action: SeminarParticipationQuickAction.alternateAngle,
                  activeIntentId: activeIntentId,
                  isSubmitting: isSubmitting,
                  label: l10n.aiSeminarParticipationAlternate,
                  icon: Icons.change_circle_outlined,
                  onPressed: onQuickAction,
                ),
                _QuickActionChip(
                  sessionId: sessionId,
                  action: SeminarParticipationQuickAction.refreshEvidence,
                  activeIntentId: activeIntentId,
                  isSubmitting: isSubmitting,
                  label: l10n.aiSeminarParticipationRefreshEvidence,
                  icon: Icons.travel_explore_outlined,
                  onPressed: onQuickAction,
                ),
                _QuickActionChip(
                  sessionId: sessionId,
                  action: SeminarParticipationQuickAction.synthesize,
                  activeIntentId: activeIntentId,
                  isSubmitting: isSubmitting,
                  label: l10n.aiSeminarParticipationSynthesize,
                  icon: Icons.summarize_outlined,
                  onPressed: onQuickAction,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final rolePicker = _RolePicker(
                  sessionId: sessionId,
                  roles: roles,
                  selectedRole: selectedRole,
                  enabled: !isSubmitting,
                  roleLabelBuilder: roleLabelBuilder,
                  onRoleChanged: onRoleChanged,
                );
                final input = _ParticipationInput(
                  sessionId: sessionId,
                  controller: controller,
                  enabled: !isSubmitting,
                  canSend: canSend,
                  isSending: activeIntentId == 'send',
                  onDraftChanged: onDraftChanged,
                  onSend: onSend,
                );
                if (constraints.maxWidth >= 620) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 180, child: rolePicker),
                      const SizedBox(width: 8),
                      Expanded(child: input),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rolePicker,
                    const SizedBox(height: 8),
                    input,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SeminarDisagreementParticipationChips extends StatelessWidget {
  const SeminarDisagreementParticipationChips({
    super.key,
    required this.sessionId,
    required this.disagreements,
    required this.isSubmitting,
    required this.onContinue,
    required this.onVerifyEvidence,
  });

  final String sessionId;
  final List<String> disagreements;
  final bool isSubmitting;
  final ValueChanged<String> onContinue;
  final ValueChanged<String> onVerifyEvidence;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < disagreements.length; index++) ...[
          _DisagreementChipRow(
            sessionId: sessionId,
            disagreement: disagreements[index],
            index: index,
            isSubmitting: isSubmitting,
            onContinue: onContinue,
            onVerifyEvidence: onVerifyEvidence,
          ),
          if (index != disagreements.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DismissibleHint extends StatelessWidget {
  const _DismissibleHint({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.aiSeminarParticipationHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.fg(context),
                      height: 1.28,
                    ),
              ),
            ),
            IconButton(
              tooltip: l10n.aiSeminarParticipationDismissHint,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: 32,
                height: 32,
              ),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.sessionId,
    required this.action,
    required this.activeIntentId,
    required this.isSubmitting,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String sessionId;
  final SeminarParticipationQuickAction action;
  final String? activeIntentId;
  final bool isSubmitting;
  final String label;
  final IconData icon;
  final ValueChanged<SeminarParticipationQuickAction> onPressed;

  @override
  Widget build(BuildContext context) {
    final isActive = activeIntentId == action.id;
    return ActionChip(
      key: ValueKey('seminar-chat-card-action-${action.id}-$sessionId'),
      avatar: isActive
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      onPressed: isSubmitting ? null : () => onPressed(action),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.sessionId,
    required this.roles,
    required this.selectedRole,
    required this.enabled,
    required this.roleLabelBuilder,
    required this.onRoleChanged,
  });

  final String sessionId;
  final List<AiSeminarRole> roles;
  final AiSeminarRole? selectedRole;
  final bool enabled;
  final SeminarRoleLabelBuilder roleLabelBuilder;
  final ValueChanged<AiSeminarRole?> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return DropdownButtonFormField<AiSeminarRole?>(
      key: ValueKey('seminar-chat-card-role-$sessionId'),
      initialValue: selectedRole,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      ),
      items: [
        DropdownMenuItem<AiSeminarRole?>(
          value: null,
          child: Text(l10n.aiSeminarParticipationDirectorAssign),
        ),
        for (final role in roles)
          DropdownMenuItem<AiSeminarRole?>(
            value: role,
            child: Text(roleLabelBuilder(role.asString)),
          ),
      ],
      onChanged: enabled ? onRoleChanged : null,
    );
  }
}

class _ParticipationInput extends StatelessWidget {
  const _ParticipationInput({
    required this.sessionId,
    required this.controller,
    required this.enabled,
    required this.canSend,
    required this.isSending,
    required this.onDraftChanged,
    required this.onSend,
  });

  final String sessionId;
  final TextEditingController controller;
  final bool enabled;
  final bool canSend;
  final bool isSending;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return TextField(
      key: ValueKey('seminar-chat-card-reply-$sessionId'),
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 1,
      textInputAction: TextInputAction.send,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        hintText: l10n.aiSeminarParticipationInputHint,
        suffixIcon: IconButton(
          tooltip: l10n.aiSeminarParticipationSend,
          onPressed: canSend ? onSend : null,
          icon: isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
        ),
      ),
      onChanged: onDraftChanged,
      onSubmitted: (_) {
        if (canSend) onSend();
      },
    );
  }
}

class _DisagreementChipRow extends StatelessWidget {
  const _DisagreementChipRow({
    required this.sessionId,
    required this.disagreement,
    required this.index,
    required this.isSubmitting,
    required this.onContinue,
    required this.onVerifyEvidence,
  });

  final String sessionId;
  final String disagreement;
  final int index;
  final bool isSubmitting;
  final ValueChanged<String> onContinue;
  final ValueChanged<String> onVerifyEvidence;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final suffix = index == 0 ? '' : '-$index';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withValues(alpha: 0.34),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeminarExpandableText(
              text: disagreement,
              collapsedMaxLines: 2,
              expandLabel: l10n.aiSeminarParticipationExpand,
              collapseLabel: l10n.aiSeminarParticipationCollapse,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: ValueKey(
                    'seminar-chat-card-continue-disagreement-$sessionId$suffix',
                  ),
                  avatar: const Icon(Icons.forum_outlined, size: 16),
                  label: Text(l10n.aiSeminarDisagreementContinue),
                  onPressed:
                      isSubmitting ? null : () => onContinue(disagreement),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: ClaudePalette.divider(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                ActionChip(
                  key: ValueKey(
                    'seminar-chat-card-refresh-disagreement-$sessionId$suffix',
                  ),
                  avatar: const Icon(Icons.travel_explore_outlined, size: 16),
                  label: Text(l10n.aiSeminarDisagreementVerifyEvidence),
                  onPressed: isSubmitting
                      ? null
                      : () => onVerifyEvidence(disagreement),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: ClaudePalette.divider(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
