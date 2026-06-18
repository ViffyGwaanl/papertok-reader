import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/setup/seminar_run_card_setup_widgets.dart';

class SeminarRunCardResumeBanner extends StatelessWidget {
  const SeminarRunCardResumeBanner({
    required this.card,
    required this.runtimeState,
    required this.showDetails,
    required this.isSubmitting,
    required this.zh,
    required this.roleLabelBuilder,
    required this.onOpen,
    required this.onContinue,
    super.key,
  });

  final AiSeminarRunCardMeta card;
  final AiSeminarRuntimeState runtimeState;
  final bool showDetails;
  final bool isSubmitting;
  final bool zh;
  final SeminarRunRoleLabelBuilder roleLabelBuilder;
  final VoidCallback onOpen;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final completedRoleCount = runtimeState.turns
        .where((turn) => turn.responseText.trim().isNotEmpty)
        .length;
    final provider = runtimeState.providerDiagnostics;
    final providerLabel = provider == null || provider.modelId.trim().isEmpty
        ? ''
        : ' · ${provider.providerName} / ${provider.modelId}';
    final detail = _localized(
      zh: zh,
      zhText: '已完成 $completedRoleCount 个角色，可直接继续缺失角色，也可展开断点详情$providerLabel。',
      en: '$completedRoleCount roles completed. Continue missing roles directly, or expand checkpoint details$providerLabel.',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.5),
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
                  Icons.restore_outlined,
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
                          zhText: '可从中断处继续',
                          en: 'Resumable checkpoint',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ClaudePalette.fg(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('seminar-chat-card-continue-$sessionId'),
                  onPressed: isSubmitting ? null : onContinue,
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
                      zhText: '继续研讨',
                      en: 'Continue seminar',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey('seminar-chat-card-resume-$sessionId'),
                  onPressed: isSubmitting ? null : onOpen,
                  icon: Icon(
                    showDetails
                        ? Icons.expand_less_outlined
                        : Icons.expand_more_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _localized(
                      zh: zh,
                      zhText: showDetails ? '收起断点' : '断点详情',
                      en: showDetails
                          ? 'Hide checkpoint'
                          : 'Checkpoint details',
                    ),
                  ),
                ),
              ],
            ),
            if (showDetails) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: ClaudePalette.divider(context)),
              const SizedBox(height: 10),
              SeminarRunCardResumeDetails(
                runtimeState: runtimeState,
                zh: zh,
                roleLabelBuilder: roleLabelBuilder,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SeminarRunCardResumeDetails extends StatelessWidget {
  const SeminarRunCardResumeDetails({
    required this.runtimeState,
    required this.zh,
    required this.roleLabelBuilder,
    super.key,
  });

  final AiSeminarRuntimeState runtimeState;
  final bool zh;
  final SeminarRunRoleLabelBuilder roleLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final completedRoles = _seminarResumeCompletedRoleLabels(
      runtimeState,
      roleLabelBuilder,
    );
    final completedRoleText = completedRoles.isEmpty
        ? _localized(
            zh: zh,
            zhText: '暂无已完成角色',
            en: 'No completed roles yet',
          )
        : completedRoles.join('、');
    final evidenceCount = runtimeState.evidenceBundle?.evidence.length ?? 0;
    final evidenceText = _localized(
      zh: zh,
      zhText: '$evidenceCount 条证据',
      en: '$evidenceCount evidence items',
    );
    final providerText = seminarResumeProviderLabel(runtimeState);
    final nextStepText = _seminarResumeNextStepLabel(
      runtimeState,
      zh: zh,
      roleLabelBuilder: roleLabelBuilder,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localized(
            zh: zh,
            zhText: '断点详情',
            en: 'Checkpoint details',
          ),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: ClaudePalette.fg(context),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        SeminarRunCardResumeDetailRow(
          icon: Icons.history_toggle_off_outlined,
          label: _localized(
            zh: zh,
            zhText: '断点状态',
            en: 'Checkpoint',
          ),
          value: _localized(
            zh: zh,
            zhText: '可继续 · 已完成：$completedRoleText',
            en: 'Resumable · completed: $completedRoleText',
          ),
        ),
        SeminarRunCardResumeDetailRow(
          icon: Icons.manage_search_outlined,
          label: _localized(
            zh: zh,
            zhText: '已保存证据',
            en: 'Saved evidence',
          ),
          value: evidenceText,
        ),
        SeminarRunCardResumeDetailRow(
          icon: Icons.route_outlined,
          label: _localized(
            zh: zh,
            zhText: '下一步',
            en: 'Next step',
          ),
          value: nextStepText,
        ),
        if (providerText.isNotEmpty)
          SeminarRunCardResumeDetailRow(
            icon: Icons.memory_outlined,
            label: _localized(
              zh: zh,
              zhText: '模型',
              en: 'Model',
            ),
            value: providerText,
          ),
      ],
    );
  }
}

class SeminarRunCardResumeDetailRow extends StatelessWidget {
  const SeminarRunCardResumeDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 17,
            color: ClaudePalette.fg(context).withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.fg(context),
                    height: 1.32,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

bool shouldShowSeminarCardResumeBanner(
  AiSeminarRunCardMeta card,
  AiSeminarRuntimeState runtimeState,
) {
  final sessionId = card.sessionId?.trim();
  if (sessionId == null || sessionId.isEmpty) return false;
  return runtimeState.session?.id == sessionId &&
      runtimeState.canResumeRestoredRunning;
}

String seminarResumeProviderLabel(AiSeminarRuntimeState runtimeState) {
  final diagnostics = runtimeState.providerDiagnostics;
  final diagnosticsProvider = diagnostics?.providerName.trim() ?? '';
  final diagnosticsModel = diagnostics?.modelId.trim() ?? '';
  if (diagnosticsProvider.isNotEmpty || diagnosticsModel.isNotEmpty) {
    return [
      if (diagnosticsProvider.isNotEmpty) diagnosticsProvider,
      if (diagnosticsModel.isNotEmpty) diagnosticsModel,
    ].join(' / ');
  }

  final billing = runtimeState.session?.billingContext;
  final providerName = billing?.providerName.trim() ?? '';
  final modelId = billing?.modelId.trim() ?? '';
  return [
    if (providerName.isNotEmpty) providerName,
    if (modelId.isNotEmpty) modelId,
  ].join(' / ');
}

List<String> _seminarResumeCompletedRoleLabels(
  AiSeminarRuntimeState runtimeState,
  SeminarRunRoleLabelBuilder roleLabelBuilder,
) {
  final seen = <AiSeminarRole>{};
  final labels = <String>[];
  for (final turn in runtimeState.turns) {
    if (turn.responseText.trim().isEmpty || !seen.add(turn.role)) continue;
    labels.add(roleLabelBuilder(turn.role));
  }
  return labels;
}

String _seminarResumeNextStepLabel(
  AiSeminarRuntimeState runtimeState, {
  required bool zh,
  required SeminarRunRoleLabelBuilder roleLabelBuilder,
}) {
  final completed = runtimeState.turns
      .where((turn) => turn.responseText.trim().isNotEmpty)
      .map((turn) => turn.role)
      .toSet();
  final roles = runtimeState.session?.roles ?? AiSeminarRole.defaultRoles;
  for (final role in roles) {
    if (!completed.contains(role)) {
      final label = roleLabelBuilder(role);
      return _localized(
        zh: zh,
        zhText: '继续 $label',
        en: 'Continue $label',
      );
    }
  }
  return _localized(
    zh: zh,
    zhText: '出总结',
    en: 'Synthesize',
  );
}

String _localized({
  required bool zh,
  required String zhText,
  required String en,
}) {
  return zh ? zhText : en;
}
