import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class AiSeminarRuntimePage extends ConsumerStatefulWidget {
  const AiSeminarRuntimePage({
    super.key,
    this.initialQuestion,
    this.bookId,
    this.autoStart = false,
  });

  final String? initialQuestion;
  final int? bookId;
  final bool autoStart;

  @override
  ConsumerState<AiSeminarRuntimePage> createState() =>
      _AiSeminarRuntimePageState();
}

class _AiSeminarRuntimePageState extends ConsumerState<AiSeminarRuntimePage> {
  late final TextEditingController _questionController;
  late final TextEditingController _roleOutputBudgetController;
  late final TextEditingController _runBudgetController;
  late final TextEditingController _runCostCapController;
  bool _autoStarted = false;
  bool _discardedMismatchedEntryState = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(
      text: widget.initialQuestion?.trim() ?? '',
    );
    _roleOutputBudgetController = TextEditingController();
    _runBudgetController = TextEditingController();
    _runCostCapController = TextEditingController();
    if (widget.autoStart && _questionController.text.trim().isNotEmpty) {
      Future.microtask(_start);
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _roleOutputBudgetController.dispose();
    _runBudgetController.dispose();
    _runCostCapController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_autoStarted && widget.autoStart) return;
    _autoStarted = true;
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    final diagnostics = ref.read(aiSeminarRuntimeProvider).providerDiagnostics;
    await ref.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 'seminar-${DateTime.now().millisecondsSinceEpoch}',
            question: question,
            bookId: widget.bookId,
            budgetPolicy: _budgetPolicyFromInputs(diagnostics),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rawState = ref.watch(aiSeminarRuntimeProvider);
    final hasMismatchedEntryState = _hasMismatchedEntryState(rawState);
    if (hasMismatchedEntryState) {
      _scheduleDiscardMismatchedEntryState();
    }
    final state = hasMismatchedEntryState
        ? AiSeminarRuntimeState.initial(
            providerDiagnostics:
                ref.watch(aiSeminarProviderContextServiceProvider).resolve(),
          )
        : rawState;
    final busy = state.status == AiSeminarRunStatus.running;

    return SettingsSubpageScaffold(
      title: l10n.aiSkillSeminarModeName,
      actions: [
        if (state.canCancel)
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () =>
                ref.read(aiSeminarRuntimeProvider.notifier).cancel(),
          ),
        if (state.canRetry)
          IconButton(
            tooltip: l10n.commonRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(aiSeminarRuntimeProvider.notifier).retry(),
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            l10n.aiSkillSeminarModeDesc,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 5,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Seminar question',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _ProviderReadinessSection(
            diagnostics: state.providerDiagnostics,
          ),
          const SizedBox(height: 10),
          _BudgetSection(
            roleOutputBudgetController: _roleOutputBudgetController,
            runBudgetController: _runBudgetController,
            runCostCapController: _runCostCapController,
            diagnostics: state.providerDiagnostics,
            enabled: !busy,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.groups_2_outlined),
                label: const Text('Start Seminar'),
                onPressed: busy ? null : _start,
              ),
              const SizedBox(width: 8),
              if (state.canRetry)
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.commonRetry),
                  onPressed: () =>
                      ref.read(aiSeminarRuntimeProvider.notifier).retry(),
                ),
              if (state.canCancel)
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(l10n.commonCancel),
                  onPressed: () =>
                      ref.read(aiSeminarRuntimeProvider.notifier).cancel(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _StatusBanner(state: state),
          const SizedBox(height: 12),
          _EvidenceSection(state: state),
          const SizedBox(height: 12),
          _RolesSection(state: state),
          const SizedBox(height: 12),
          _WhiteboardSection(entries: state.whiteboardEntries),
          const SizedBox(height: 12),
          _SynthesisSection(state: state),
        ],
      ),
    );
  }

  AiSeminarBudgetPolicy? _budgetPolicyFromInputs(
    AiSeminarProviderDiagnostics? diagnostics,
  ) {
    final maxRoleOutputTokens =
        _positiveIntOrNull(_roleOutputBudgetController.text);
    final maxRunTokens = _positiveIntOrNull(_runBudgetController.text);
    final maxRunCostUsd = _positiveDoubleOrNull(_runCostCapController.text);
    final hasPricing = diagnostics?.hasPricingMetadata == true;
    final policy = AiSeminarBudgetPolicy(
      maxRoleOutputTokens: maxRoleOutputTokens,
      maxRunTokens: maxRunTokens,
      maxRunCostUsd: hasPricing ? maxRunCostUsd : null,
      inputCostPerMillionTokens:
          hasPricing ? diagnostics!.inputCostPerMillionTokens : null,
      outputCostPerMillionTokens:
          hasPricing ? diagnostics!.outputCostPerMillionTokens : null,
      cacheReadCostPerMillionTokens:
          hasPricing ? diagnostics!.cacheReadCostPerMillionTokens : null,
      cacheWriteCostPerMillionTokens:
          hasPricing ? diagnostics!.cacheWriteCostPerMillionTokens : null,
      costPriceSource: hasPricing ? diagnostics!.costPriceSource : null,
    ).normalized;
    return policy.hasLimits ? policy : null;
  }

  int? _positiveIntOrNull(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  double? _positiveDoubleOrNull(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  bool _hasMismatchedEntryState(AiSeminarRuntimeState state) {
    if (state.session == null) return false;
    final entryQuestion = widget.initialQuestion?.trim();
    final hasScopedEntry =
        widget.bookId != null || (entryQuestion?.isNotEmpty ?? false);
    if (!hasScopedEntry) return false;
    final session = state.session!;
    if (widget.bookId != null && session.bookId != widget.bookId) {
      return true;
    }
    if (entryQuestion != null &&
        entryQuestion.isNotEmpty &&
        session.question.trim() != entryQuestion) {
      return true;
    }
    return false;
  }

  void _scheduleDiscardMismatchedEntryState() {
    if (_discardedMismatchedEntryState) return;
    _discardedMismatchedEntryState = true;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(aiSeminarRuntimeProvider.notifier).discardLocalRuntimeState();
    });
  }
}

class _BudgetSection extends StatelessWidget {
  const _BudgetSection({
    required this.roleOutputBudgetController,
    required this.runBudgetController,
    required this.runCostCapController,
    required this.diagnostics,
    required this.enabled,
  });

  final TextEditingController roleOutputBudgetController;
  final TextEditingController runBudgetController;
  final TextEditingController runCostCapController;
  final AiSeminarProviderDiagnostics? diagnostics;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasPricing = diagnostics?.hasPricingMetadata == true;
    final pricingSource = diagnostics?.costPriceSource?.trim();
    return _Section(
      title: 'Local budget guardrails',
      icon: Icons.speed_outlined,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final fields = <Widget>[
              TextField(
                controller: roleOutputBudgetController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Role output token budget',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: runBudgetController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Run token budget',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: runCostCapController,
                enabled: enabled && hasPricing,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Run cost cap USD',
                  border: OutlineInputBorder(),
                ),
              ),
            ];
            if (narrow) {
              return Column(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    fields[i],
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: fields[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          hasPricing
              ? 'Uses provider-reported token usage when available and pricing metadata for estimated USD caps; provider invoices may differ.'
              : 'Uses local token estimates to stop the next Seminar step; provider billing may differ.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
        if (hasPricing) ...[
          const SizedBox(height: 4),
          Text(
            'Pricing: ${pricingSource?.isNotEmpty == true ? pricingSource : 'provider capability metadata'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Cost cap unavailable until pricing metadata is available.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
        ],
      ],
    );
  }
}

class _ProviderReadinessSection extends StatelessWidget {
  const _ProviderReadinessSection({required this.diagnostics});

  final AiSeminarProviderDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final d = diagnostics;
    if (d == null) {
      return const _Section(
        title: 'Provider readiness',
        icon: Icons.memory_outlined,
        children: [
          Text('Provider diagnostics are not available yet.'),
        ],
      );
    }

    final capabilityLine = [
      if (d.contextWindow != null)
        'Context: ${_formatTokenCount(d.contextWindow!)}',
      if (d.maxOutputTokens != null)
        'Max output: ${_formatTokenCount(d.maxOutputTokens!)}',
    ].join(' · ');
    final warnings = d.warnings;
    return _Section(
      title: 'Provider readiness',
      icon: Icons.memory_outlined,
      children: [
        Row(
          children: [
            Icon(
              d.seminarReady ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${d.providerName} · ${d.modelId.isEmpty ? 'No model selected' : d.modelId}',
              ),
            ),
          ],
        ),
        if (capabilityLine.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(capabilityLine),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _TinyChip(label: _capabilityLabel('Tools', d.supportsTools)),
            _TinyChip(label: _capabilityLabel('Vision', d.supportsImages)),
            _TinyChip(
              label: _capabilityLabel('Thinking', d.supportsThinking),
            ),
            _TinyChip(
              label: _capabilityLabel('Streaming', d.supportsStreaming),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_providerCostLine(d)),
        if (d.costUnknownReason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            d.costUnknownReason!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
        ],
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final warning in warnings)
            Text(
              warning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});

  final AiSeminarRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final error = state.error?.trim();
    final backgroundJob = state.backgroundJob;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(state.status)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error == null || error.isEmpty
                        ? 'Status: ${state.status.asString}'
                        : error,
                  ),
                ),
                _TinyChip(label: state.status.asString),
              ],
            ),
            if (state.restoredFromLocalCache) ...[
              const SizedBox(height: 6),
              Text(
                state.status == AiSeminarRunStatus.cancelled
                    ? 'Recovered interrupted local Seminar state. Retry to run it again.'
                    : 'Recovered local Seminar state from this device.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
            if (backgroundJob != null) ...[
              const SizedBox(height: 6),
              Text(
                'Background job: ${backgroundJob.status.asString} · '
                '${backgroundJob.id}',
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

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.state});

  final AiSeminarRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final evidence = state.evidenceBundle?.evidence ?? const [];
    return _Section(
      title: l10n.conceptGraphEvidenceTitle,
      icon: Icons.link_outlined,
      children: evidence.isEmpty
          ? [Text(l10n.conceptGraphNoEvidence)]
          : [
              for (final item in evidence)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.article_outlined),
                  title: Text(item.text),
                  subtitle: Text('${item.id} · ${item.scope.asString}'),
                ),
            ],
    );
  }
}

class _RolesSection extends StatelessWidget {
  const _RolesSection({required this.state});

  final AiSeminarRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final turns = state.turns;
    final activeRole = state.activeRole;
    final children = <Widget>[];
    final tokenUsage = state.tokenUsage;
    final billingSnapshot = state.lastRun?.billingSnapshot;
    if (tokenUsage != null) {
      final summary = _tokenUsageSummary(tokenUsage);
      final estimatedCost = state.lastRun?.estimatedCostUsd;
      final priceSource = state.lastRun?.costPriceSource?.trim();
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.title}: ${_formatTokenCount(tokenUsage.totalTokens)} tokens '
              '(${_formatTokenCount(tokenUsage.inputTokens)} in / '
              '${_formatTokenCount(tokenUsage.outputTokens)} out)',
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.subtitle} · ${tokenUsage.estimationMethod}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
            if (estimatedCost != null) ...[
              const SizedBox(height: 4),
              Text(
                'Estimated cost, not invoice: '
                '\$${estimatedCost.toStringAsFixed(4)}'
                '${priceSource?.isNotEmpty == true ? ' · $priceSource' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ],
        ),
      );
    }
    if (billingSnapshot != null) {
      final pricingSource = billingSnapshot.pricingSource?.trim();
      final invoiceReason = billingSnapshot.invoiceReason?.trim();
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (children.isNotEmpty) const Divider(height: 20),
            Text(
              'Billing reconciliation',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Usage snapshot: '
              '${_billingUsageLabel(billingSnapshot.usageSnapshot)}',
            ),
            Text(
              'Pricing snapshot: '
              '${pricingSource?.isNotEmpty == true ? pricingSource : 'Unavailable'}',
            ),
            Text(
              'Invoice reconciliation: '
              '${_invoiceStatusLabel(billingSnapshot.invoiceStatus)}',
            ),
            if (invoiceReason?.isNotEmpty == true)
              Text(
                invoiceReason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
          ],
        ),
      );
    }
    for (final turn in turns) {
      final usage = turn.tokenUsage;
      final usagePrefix = usage == null ? null : _roleUsagePrefix(usage);
      children.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_roleIcon(turn.role)),
          title: Text(turn.role.asString),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(turn.responseText),
              if (usage != null)
                Text(
                  '$usagePrefix: ${_formatTokenCount(usage.inputTokens)} in / '
                  '${_formatTokenCount(usage.outputTokens)} out tokens',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                      ),
                ),
            ],
          ),
        ),
      );
    }
    if (activeRole != null) {
      children.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(activeRole.asString),
          subtitle: Text(state.partialRoleText ?? ''),
        ),
      );
    }
    return _Section(
      title: 'Roles',
      icon: Icons.groups_2_outlined,
      children:
          children.isEmpty ? [const Text('No role turns yet.')] : children,
    );
  }
}

class _WhiteboardSection extends StatelessWidget {
  const _WhiteboardSection({required this.entries});

  final List<AiSeminarWhiteboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Shared whiteboard',
      icon: Icons.dashboard_customize_outlined,
      children: entries.isEmpty
          ? [const Text('No whiteboard entries yet.')]
          : [
              for (final entry in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(entry.text),
                  subtitle: Text(entry.kind.asString),
                ),
            ],
    );
  }
}

class _SynthesisSection extends ConsumerWidget {
  const _SynthesisSection({required this.state});

  final AiSeminarRuntimeState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final synthesis = state.synthesis;
    return _Section(
      title: 'Synthesis',
      icon: Icons.auto_awesome_outlined,
      children: [
        if (synthesis == null)
          const Text('No synthesis yet.')
        else ...[
          Text(synthesis.summary),
          const SizedBox(height: 8),
          Text('Supportive: ${synthesis.supportiveView}'),
          const SizedBox(height: 4),
          Text('Critical: ${synthesis.criticalView}'),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Send to Review'),
            onPressed: state.canSendToReview
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final result = await ref
                          .read(aiSeminarRuntimeProvider.notifier)
                          .sendToReview();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sent synthesis and ${result.knowledgeCardIds.length} card(s) to Review.',
                          ),
                        ),
                      );
                    } catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                : null,
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.card(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

IconData _statusIcon(AiSeminarRunStatus status) {
  return switch (status) {
    AiSeminarRunStatus.draft => Icons.edit_note_outlined,
    AiSeminarRunStatus.running => Icons.play_circle_outline,
    AiSeminarRunStatus.completed => Icons.check_circle_outline,
    AiSeminarRunStatus.needsEvidence => Icons.link_off_outlined,
    AiSeminarRunStatus.cancelled => Icons.stop_circle_outlined,
    AiSeminarRunStatus.failed => Icons.error_outline,
  };
}

IconData _roleIcon(AiSeminarRole role) {
  return switch (role) {
    AiSeminarRole.critical => Icons.report_problem_outlined,
    AiSeminarRole.supportive => Icons.thumb_up_alt_outlined,
    AiSeminarRole.synthesizer => Icons.auto_awesome_outlined,
    AiSeminarRole.verifier => Icons.verified_outlined,
  };
}

String _capabilityLabel(String label, bool? value) {
  if (value == true) return label;
  if (value == false) return 'No $label';
  return '$label unknown';
}

String _providerCostLine(AiSeminarProviderDiagnostics diagnostics) {
  if (diagnostics.estimatedCostUsd != null) {
    return 'Cost: \$${diagnostics.estimatedCostUsd!.toStringAsFixed(4)}';
  }
  if (diagnostics.hasPricingMetadata) {
    return 'Cost: pricing ready for estimated USD caps';
  }
  return 'Cost: unknown';
}

({String title, String subtitle}) _tokenUsageSummary(
  AiSeminarTokenUsage usage,
) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => (
        title: 'Provider reported usage',
        subtitle: 'Stored from provider usage metadata',
      ),
    AiSeminarTokenUsage.sourceMixed => (
        title: 'Token usage',
        subtitle: 'Mixed provider usage and local estimates',
      ),
    _ => (
        title: 'Local token estimate',
        subtitle: 'Provider billing may differ',
      ),
  };
}

String _roleUsagePrefix(AiSeminarTokenUsage usage) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => 'Provider usage',
    AiSeminarTokenUsage.sourceMixed => 'Mixed usage',
    _ => 'Local estimate',
  };
}

String _billingUsageLabel(AiSeminarTokenUsage usage) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => 'Provider metadata',
    AiSeminarTokenUsage.sourceMixed =>
      'Mixed provider metadata and local estimate',
    _ => 'Local estimate',
  };
}

String _invoiceStatusLabel(AiSeminarInvoiceReconciliationStatus status) {
  return switch (status) {
    AiSeminarInvoiceReconciliationStatus.notConnected => 'Not connected',
    AiSeminarInvoiceReconciliationStatus.reconciled => 'Reconciled',
    AiSeminarInvoiceReconciliationStatus.failed => 'Failed',
  };
}

String _formatTokenCount(int count) {
  if (count >= 1000000) {
    final value = count / 1000000;
    return value == value.roundToDouble()
        ? '${value.toInt()}M'
        : '${value.toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    final value = count / 1000;
    return value == value.roundToDouble()
        ? '${value.toInt()}K'
        : '${value.toStringAsFixed(1)}K';
  }
  return count.toString();
}
