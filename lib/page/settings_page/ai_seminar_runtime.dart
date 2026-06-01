import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';

class AiSeminarRuntimePage extends ConsumerWidget {
  const AiSeminarRuntimePage({
    super.key,
    this.initialQuestion,
    this.bookId,
    this.initialSourceRef,
    this.autoStart = false,
  });

  final String? initialQuestion;
  final int? bookId;
  final SourceRef? initialSourceRef;
  final bool autoStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final state = ref.watch(aiSeminarRuntimeProvider);
    return SettingsSubpageScaffold(
      title: l10n.aiSkillSeminarModeName,
      actions: [
        IconButton(
          tooltip: l10n.seminarConfigTitle,
          icon: const Icon(Icons.tune_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AiSeminarConfigPage()),
          ),
        ),
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
      child: AiSeminarRuntimePanel(
        initialQuestion: initialQuestion,
        bookId: bookId,
        initialSourceRef: initialSourceRef,
        autoStart: autoStart,
      ),
    );
  }
}

class AiSeminarRuntimePanel extends ConsumerStatefulWidget {
  const AiSeminarRuntimePanel({
    super.key,
    this.initialQuestion,
    this.bookId,
    this.initialSourceRef,
    this.autoStart = false,
    this.embedded = false,
    this.onClose,
    this.onOpenFullPage,
  });

  final String? initialQuestion;
  final int? bookId;
  final SourceRef? initialSourceRef;
  final bool autoStart;
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onOpenFullPage;

  @override
  ConsumerState<AiSeminarRuntimePanel> createState() =>
      _AiSeminarRuntimePanelState();
}

class _AiSeminarRuntimePanelState extends ConsumerState<AiSeminarRuntimePanel> {
  late final TextEditingController _questionController;
  late final TextEditingController _roleOutputBudgetController;
  late final TextEditingController _runBudgetController;
  late final TextEditingController _runCostCapController;
  late bool _includeVerifier;
  bool _autoStarted = false;
  bool _discardedMismatchedEntryState = false;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(
      text: widget.initialQuestion?.trim() ?? '',
    );
    _roleOutputBudgetController = TextEditingController();
    _roleOutputBudgetController.text =
        Prefs().aiSeminarDefaultRoleOutputTokenBudget?.toString() ?? '';
    _runBudgetController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunTokenBudget?.toString() ?? '',
    );
    _runCostCapController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunCostCapUsd?.toString() ?? '',
    );
    _includeVerifier = Prefs().aiSeminarIncludeVerifier;
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
            bookId: widget.initialSourceRef?.bookId ?? widget.bookId,
            sourceRefs: [
              if (widget.initialSourceRef != null) widget.initialSourceRef!,
            ],
            roles: _selectedRoles,
            budgetPolicy: _budgetPolicyFromInputs(diagnostics),
            roleProfiles: Prefs().aiSeminarRoleProfiles,
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

    final content = ListView(
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
          decoration: InputDecoration(
            labelText: l10n.seminarQuestionLabel,
            border: const OutlineInputBorder(),
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
        _AgentRolesSection(
          includeVerifier: _includeVerifier,
          enabled: !busy,
          onVerifierChanged: (value) {
            setState(() {
              _includeVerifier = value;
            });
            Prefs().aiSeminarIncludeVerifier = value;
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              icon: Icon(
                busy ? Icons.playlist_add_outlined : Icons.groups_2_outlined,
              ),
              label: Text(busy ? l10n.seminarQueue : l10n.seminarStart),
              onPressed: _start,
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
        if (_shouldShowJobQueue(state.backgroundJobs)) ...[
          const SizedBox(height: 12),
          _BackgroundJobsSection(jobs: state.backgroundJobs),
        ],
        const SizedBox(height: 12),
        _EvidenceSection(state: state),
        const SizedBox(height: 12),
        _RolesSection(state: state),
        const SizedBox(height: 12),
        _WhiteboardSection(entries: state.whiteboardEntries),
        const SizedBox(height: 12),
        _SynthesisSection(state: state),
      ],
    );

    if (!widget.embedded) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.bg(context),
        border: Border(
          top: BorderSide(color: ClaudePalette.divider(context)),
        ),
      ),
      child: Column(
        children: [
          _EmbeddedSeminarHeader(
            state: state,
            onClose: widget.onClose,
            onOpenFullPage: widget.onOpenFullPage,
          ),
          Expanded(child: content),
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
    final entryBookId = widget.initialSourceRef?.bookId ?? widget.bookId;
    final hasScopedEntry = entryBookId != null ||
        widget.initialSourceRef != null ||
        (entryQuestion?.isNotEmpty ?? false);
    if (!hasScopedEntry) return false;
    final session = state.session!;
    if (entryBookId != null && session.bookId != entryBookId) {
      return true;
    }
    final entrySourceRef = widget.initialSourceRef;
    if (entrySourceRef != null &&
        !_sessionContainsSourceRef(session, entrySourceRef)) {
      return true;
    }
    if (entryQuestion != null &&
        entryQuestion.isNotEmpty &&
        session.question.trim() != entryQuestion) {
      return true;
    }
    return false;
  }

  bool _sessionContainsSourceRef(
    AiSeminarSessionContract session,
    SourceRef entrySourceRef,
  ) {
    final entryKey = _sourceRefEntryKey(entrySourceRef);
    return session.sourceRefs
        .any((candidate) => _sourceRefEntryKey(candidate) == entryKey);
  }

  String _sourceRefEntryKey(SourceRef ref) => [
        ref.bookId ?? '',
        ref.href ?? '',
        ref.cfi ?? '',
        ref.chunkId ?? '',
        ref.jumpLink ?? '',
        ref.sourceHash ?? '',
      ].join('\u001f');

  void _scheduleDiscardMismatchedEntryState() {
    if (_discardedMismatchedEntryState) return;
    _discardedMismatchedEntryState = true;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(aiSeminarRuntimeProvider.notifier).discardLocalRuntimeState();
    });
  }

  bool _shouldShowJobQueue(List<AiSeminarBackgroundJobSnapshot> jobs) {
    if (jobs.length > 1) return true;
    return jobs.any((job) => job.isQueued);
  }

  List<AiSeminarRole> get _selectedRoles => [
        AiSeminarRole.critical,
        AiSeminarRole.supportive,
        if (_includeVerifier) AiSeminarRole.verifier,
        AiSeminarRole.synthesizer,
      ];
}

class _EmbeddedSeminarHeader extends ConsumerWidget {
  const _EmbeddedSeminarHeader({
    required this.state,
    required this.onClose,
    required this.onOpenFullPage,
  });

  final AiSeminarRuntimeState state;
  final VoidCallback? onClose;
  final VoidCallback? onOpenFullPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Material(
      color: ClaudePalette.card(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(
              Icons.groups_2_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.aiSkillSeminarModeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _TinyChip(label: _runStatusLabel(l10n, state.status)),
            IconButton(
              tooltip: l10n.seminarConfigTitle,
              icon: const Icon(Icons.tune_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiSeminarConfigPage()),
              ),
            ),
            if (state.canRetry)
              IconButton(
                tooltip: l10n.commonRetry,
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(aiSeminarRuntimeProvider.notifier).retry(),
              ),
            if (state.canCancel)
              IconButton(
                tooltip: l10n.commonCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () =>
                    ref.read(aiSeminarRuntimeProvider.notifier).cancel(),
              ),
            if (onOpenFullPage != null)
              IconButton(
                tooltip: l10n.aiChatSeminarFeatureAction,
                icon: const Icon(Icons.open_in_full_outlined),
                onPressed: onOpenFullPage,
              ),
            if (onClose != null)
              IconButton(
                tooltip: l10n.commonCancel,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

class _AgentRolesSection extends StatelessWidget {
  const _AgentRolesSection({
    required this.includeVerifier,
    required this.enabled,
    required this.onVerifierChanged,
  });

  final bool includeVerifier;
  final bool enabled;
  final ValueChanged<bool> onVerifierChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _Section(
      title: l10n.seminarAgentRolesTitle,
      icon: Icons.account_tree_outlined,
      children: [
        Text(
          l10n.seminarAgentRolesDesc,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
        const SizedBox(height: 8),
        Text(l10n.seminarAgentRolesFixed),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.verified_outlined),
          title: Text(l10n.seminarRoleVerifier),
          subtitle: Text(l10n.seminarVerifierDesc),
          value: includeVerifier,
          onChanged: enabled ? onVerifierChanged : null,
        ),
      ],
    );
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
    final l10n = L10n.of(context);
    final hasPricing = diagnostics?.hasPricingMetadata == true;
    final pricingSource = diagnostics?.costPriceSource?.trim();
    return _Section(
      title: l10n.seminarBudgetGuardrails,
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
                decoration: InputDecoration(
                  labelText: l10n.seminarRoleOutputBudget,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: runBudgetController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.seminarRunTokenBudget,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: runCostCapController,
                enabled: enabled && hasPricing,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.seminarRunCostCapUsd,
                  border: const OutlineInputBorder(),
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
              ? l10n.seminarBudgetPricingDesc
              : l10n.seminarBudgetLocalDesc,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
        if (hasPricing) ...[
          const SizedBox(height: 4),
          Text(
            l10n.seminarPricingLine(
              pricingSource?.isNotEmpty == true
                  ? pricingSource!
                  : l10n.seminarPricingFallback,
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            l10n.seminarCostCapUnavailable,
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
    final l10n = L10n.of(context);
    final d = diagnostics;
    if (d == null) {
      return _Section(
        title: l10n.seminarProviderReadiness,
        icon: Icons.memory_outlined,
        children: [
          Text(l10n.seminarProviderDiagnosticsUnavailable),
        ],
      );
    }

    final capabilityLine = [
      if (d.contextWindow != null)
        l10n.seminarContextLine(_formatTokenCount(d.contextWindow!)),
      if (d.maxOutputTokens != null)
        l10n.seminarMaxOutputLine(_formatTokenCount(d.maxOutputTokens!)),
    ].join(' · ');
    final warnings = d.warnings;
    return _Section(
      title: l10n.seminarProviderReadiness,
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
                '${d.providerName} · ${d.modelId.isEmpty ? l10n.seminarNoModelSelected : d.modelId}',
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
            _TinyChip(
              label: _capabilityLabel(
                l10n,
                l10n.seminarTools,
                d.supportsTools,
              ),
            ),
            _TinyChip(
              label: _capabilityLabel(
                l10n,
                l10n.seminarVision,
                d.supportsImages,
              ),
            ),
            _TinyChip(
              label: _capabilityLabel(
                l10n,
                l10n.seminarThinking,
                d.supportsThinking,
              ),
            ),
            _TinyChip(
              label: _capabilityLabel(
                l10n,
                l10n.seminarStreaming,
                d.supportsStreaming,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_providerCostLine(l10n, d)),
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
    final l10n = L10n.of(context);
    final error = state.error?.trim();
    final backgroundJob = state.backgroundJob;
    final statusLabel = _runStatusLabel(l10n, state.status);
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
                        ? l10n.seminarStatusLine(statusLabel)
                        : error,
                  ),
                ),
                _TinyChip(label: statusLabel),
              ],
            ),
            if (state.restoredFromLocalCache) ...[
              const SizedBox(height: 6),
              Text(
                state.status == AiSeminarRunStatus.cancelled
                    ? l10n.seminarRecoveredInterrupted
                    : l10n.seminarRecoveredLocal,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
            if (backgroundJob != null) ...[
              const SizedBox(height: 6),
              Text(
                l10n.seminarBackgroundJobLine(
                  _backgroundJobStatusLabel(l10n, backgroundJob.status),
                  backgroundJob.id,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
            if (_directorNextIntentLine(context, state.directorState)
                case final directorLine?) ...[
              const SizedBox(height: 6),
              Text(
                directorLine,
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

String? _directorNextIntentLine(
  BuildContext context,
  AiSeminarDirectorState? director,
) {
  if (director == null) return null;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (director.nextIntent) {
    AiSeminarDirectorNextIntent.askUser =>
      zh ? '主持人下一步：邀请读者参与讨论' : 'Director next: ask reader',
    AiSeminarDirectorNextIntent.refreshEvidence =>
      zh ? '主持人下一步：重新检索证据' : 'Director next: refresh evidence',
    AiSeminarDirectorNextIntent.synthesize =>
      zh ? '主持人下一步：整理阶段结论' : 'Director next: synthesize',
    _ => null,
  };
}

class _BackgroundJobsSection extends StatelessWidget {
  const _BackgroundJobsSection({required this.jobs});

  final List<AiSeminarBackgroundJobSnapshot> jobs;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final visibleJobs = jobs.reversed.take(6).toList(growable: false);
    return _Section(
      title: l10n.seminarJobQueue,
      icon: Icons.playlist_add_check_outlined,
      children: [
        for (final job in visibleJobs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_jobIcon(job.status), size: 20),
            title: Text(
              '${_backgroundJobStatusLabel(l10n, job.status)} · ${job.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                job.session?.question.trim().isNotEmpty == true
                    ? job.session!.question.trim()
                    : job.sessionId,
                if (job.message?.trim().isNotEmpty == true) job.message!.trim(),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                  ),
            ),
            trailing: job.isQueued
                ? Consumer(
                    builder: (context, ref, _) => IconButton(
                      tooltip: l10n.seminarCancelQueued,
                      icon: const Icon(Icons.close),
                      onPressed: () => ref
                          .read(aiSeminarRuntimeProvider.notifier)
                          .cancelBackgroundJob(job.id),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  IconData _jobIcon(AiSeminarBackgroundJobStatus status) {
    return switch (status) {
      AiSeminarBackgroundJobStatus.running => Icons.play_circle_outline,
      AiSeminarBackgroundJobStatus.queued => Icons.schedule_outlined,
      AiSeminarBackgroundJobStatus.completed => Icons.check_circle_outline,
      AiSeminarBackgroundJobStatus.needsEvidence => Icons.link_off_outlined,
      AiSeminarBackgroundJobStatus.cancelled => Icons.cancel_outlined,
      AiSeminarBackgroundJobStatus.failed => Icons.error_outline,
      AiSeminarBackgroundJobStatus.interrupted => Icons.pause_circle_outline,
    };
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
                  subtitle: Text(
                    '${item.id} · ${_evidenceScopeLabel(l10n, item.scope)}',
                  ),
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
    final l10n = L10n.of(context);
    final turns = state.turns;
    final activeRole = state.activeRole;
    final children = <Widget>[];
    final tokenUsage = state.tokenUsage;
    final billingSnapshot = state.lastRun?.billingSnapshot;
    if (tokenUsage != null) {
      final summary = _tokenUsageSummary(l10n, tokenUsage);
      final estimatedCost = state.lastRun?.estimatedCostUsd;
      final priceSource = state.lastRun?.costPriceSource?.trim();
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.seminarTokenUsageLine(
                summary.title,
                _formatTokenCount(tokenUsage.totalTokens),
                _formatTokenCount(tokenUsage.inputTokens),
                _formatTokenCount(tokenUsage.outputTokens),
              ),
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
                priceSource?.isNotEmpty == true
                    ? l10n.seminarEstimatedCostWithSource(
                        estimatedCost.toStringAsFixed(4),
                        priceSource!,
                      )
                    : l10n.seminarEstimatedCostNotInvoice(
                        estimatedCost.toStringAsFixed(4),
                      ),
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
              l10n.seminarBillingReconciliation,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.seminarUsageSnapshot(
                _billingUsageLabel(l10n, billingSnapshot.usageSnapshot),
              ),
            ),
            Text(
              l10n.seminarPricingSnapshot(
                pricingSource?.isNotEmpty == true
                    ? pricingSource!
                    : l10n.seminarUnavailable,
              ),
            ),
            Text(
              l10n.seminarInvoiceReconciliation(
                _invoiceStatusLabel(l10n, billingSnapshot.invoiceStatus),
              ),
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
      final usagePrefix = usage == null ? null : _roleUsagePrefix(l10n, usage);
      children.add(
        _RoleTurnTile(
          turn: turn,
          usage: usage,
          usagePrefix: usagePrefix,
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
          title: Text(_seminarRoleLabel(l10n, activeRole)),
          subtitle: StyledMarkdown(
            data: state.partialRoleText ?? '',
            selectable: false,
          ),
        ),
      );
    }
    return _Section(
      title: l10n.seminarRolesTitle,
      icon: Icons.groups_2_outlined,
      children: children.isEmpty ? [Text(l10n.seminarNoRoleTurns)] : children,
    );
  }
}

class _RoleTurnTile extends StatelessWidget {
  const _RoleTurnTile({
    required this.turn,
    required this.usage,
    required this.usagePrefix,
  });

  final AiSeminarRoleTurn turn;
  final AiSeminarTokenUsage? usage;
  final String? usagePrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Icon(_roleIcon(turn.role), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _seminarRoleLabel(l10n, turn.role),
                      style: theme.textTheme.titleSmall,
                    ),
                    for (final evidenceId in turn.evidenceRefIds.take(4))
                      _TinyChip(label: evidenceId),
                  ],
                ),
                const SizedBox(height: 6),
                StyledMarkdown(
                  data: turn.responseText,
                  selectable: false,
                ),
                if (usage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.seminarRoleUsageLine(
                      usagePrefix!,
                      _formatTokenCount(usage!.inputTokens),
                      _formatTokenCount(usage!.outputTokens),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
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

class _WhiteboardSection extends StatelessWidget {
  const _WhiteboardSection({required this.entries});

  final List<AiSeminarWhiteboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _Section(
      title: l10n.seminarSharedWhiteboard,
      icon: Icons.dashboard_customize_outlined,
      children: entries.isEmpty
          ? [Text(l10n.seminarNoWhiteboardEntries)]
          : [
              for (final entry in entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(entry.text),
                  subtitle: Text(_whiteboardKindLabel(l10n, entry.kind)),
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
    final l10n = L10n.of(context);
    final synthesis = state.synthesis;
    return _Section(
      title: l10n.seminarSynthesisTitle,
      icon: Icons.auto_awesome_outlined,
      children: [
        if (synthesis == null)
          Text(l10n.seminarNoSynthesis)
        else ...[
          StyledMarkdown(
            data: synthesis.summary,
            selectable: false,
          ),
          const SizedBox(height: 8),
          _SynthesisViewTile(
            icon: Icons.thumb_up_alt_outlined,
            label: l10n.seminarRoleSupportive,
            text: synthesis.supportiveView,
          ),
          const SizedBox(height: 4),
          _SynthesisViewTile(
            icon: Icons.report_problem_outlined,
            label: l10n.seminarRoleCritical,
            text: synthesis.criticalView,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l10n.seminarSendToReview),
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
                            l10n.seminarSentToReview(
                              result.knowledgeCardIds.length,
                            ),
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

class _SynthesisViewTile extends StatelessWidget {
  const _SynthesisViewTile({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: ClaudePalette.secondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  StyledMarkdown(
                    data: text,
                    selectable: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

String _capabilityLabel(L10n l10n, String label, bool? value) {
  if (value == true) return l10n.seminarCapabilityYes(label);
  if (value == false) return l10n.seminarCapabilityNo(label);
  return l10n.seminarCapabilityUnknown(label);
}

String _providerCostLine(
  L10n l10n,
  AiSeminarProviderDiagnostics diagnostics,
) {
  if (diagnostics.estimatedCostUsd != null) {
    return l10n.seminarCostValue(
      diagnostics.estimatedCostUsd!.toStringAsFixed(4),
    );
  }
  if (diagnostics.hasPricingMetadata) {
    return l10n.seminarCostPricingReady;
  }
  return l10n.seminarCostUnknown;
}

({String title, String subtitle}) _tokenUsageSummary(
  L10n l10n,
  AiSeminarTokenUsage usage,
) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => (
        title: l10n.seminarProviderReportedUsage,
        subtitle: l10n.seminarProviderReportedUsageDesc,
      ),
    AiSeminarTokenUsage.sourceMixed => (
        title: l10n.seminarTokenUsage,
        subtitle: l10n.seminarTokenUsageDesc,
      ),
    _ => (
        title: l10n.seminarLocalTokenEstimate,
        subtitle: l10n.seminarLocalTokenEstimateDesc,
      ),
  };
}

String _roleUsagePrefix(L10n l10n, AiSeminarTokenUsage usage) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => l10n.seminarProviderUsage,
    AiSeminarTokenUsage.sourceMixed => l10n.seminarMixedUsage,
    _ => l10n.seminarLocalEstimate,
  };
}

String _billingUsageLabel(L10n l10n, AiSeminarTokenUsage usage) {
  return switch (usage.source) {
    AiSeminarTokenUsage.sourceProviderReported => l10n.seminarProviderMetadata,
    AiSeminarTokenUsage.sourceMixed => l10n.seminarMixedProviderLocal,
    _ => l10n.seminarLocalEstimate,
  };
}

String _invoiceStatusLabel(
  L10n l10n,
  AiSeminarInvoiceReconciliationStatus status,
) {
  return switch (status) {
    AiSeminarInvoiceReconciliationStatus.notConnected =>
      l10n.seminarInvoiceNotConnected,
    AiSeminarInvoiceReconciliationStatus.reconciled =>
      l10n.seminarInvoiceReconciled,
    AiSeminarInvoiceReconciliationStatus.failed => l10n.seminarInvoiceFailed,
  };
}

String _runStatusLabel(L10n l10n, AiSeminarRunStatus status) {
  return switch (status) {
    AiSeminarRunStatus.draft => l10n.seminarRunStatusDraft,
    AiSeminarRunStatus.running => l10n.seminarRunStatusRunning,
    AiSeminarRunStatus.completed => l10n.seminarRunStatusCompleted,
    AiSeminarRunStatus.needsEvidence => l10n.seminarRunStatusNeedsEvidence,
    AiSeminarRunStatus.cancelled => l10n.seminarRunStatusCancelled,
    AiSeminarRunStatus.failed => l10n.seminarRunStatusFailed,
  };
}

String _backgroundJobStatusLabel(
  L10n l10n,
  AiSeminarBackgroundJobStatus status,
) {
  return switch (status) {
    AiSeminarBackgroundJobStatus.running => l10n.seminarJobStatusRunning,
    AiSeminarBackgroundJobStatus.queued => l10n.seminarJobStatusQueued,
    AiSeminarBackgroundJobStatus.completed => l10n.seminarJobStatusCompleted,
    AiSeminarBackgroundJobStatus.needsEvidence =>
      l10n.seminarJobStatusNeedsEvidence,
    AiSeminarBackgroundJobStatus.cancelled => l10n.seminarJobStatusCancelled,
    AiSeminarBackgroundJobStatus.failed => l10n.seminarJobStatusFailed,
    AiSeminarBackgroundJobStatus.interrupted =>
      l10n.seminarJobStatusInterrupted,
  };
}

String _seminarRoleLabel(L10n l10n, AiSeminarRole role) {
  return switch (role) {
    AiSeminarRole.critical => l10n.seminarRoleCritical,
    AiSeminarRole.supportive => l10n.seminarRoleSupportive,
    AiSeminarRole.synthesizer => l10n.seminarRoleSynthesizer,
    AiSeminarRole.verifier => l10n.seminarRoleVerifier,
  };
}

String _whiteboardKindLabel(L10n l10n, AiSeminarWhiteboardKind kind) {
  return switch (kind) {
    AiSeminarWhiteboardKind.claim => l10n.seminarWhiteboardClaim,
    AiSeminarWhiteboardKind.evidenceRef => l10n.seminarWhiteboardEvidenceRef,
    AiSeminarWhiteboardKind.disagreement => l10n.seminarWhiteboardDisagreement,
    AiSeminarWhiteboardKind.openQuestion => l10n.seminarWhiteboardOpenQuestion,
    AiSeminarWhiteboardKind.candidateCard =>
      l10n.seminarWhiteboardCandidateCard,
    AiSeminarWhiteboardKind.reviewSuggestion =>
      l10n.seminarWhiteboardReviewSuggestion,
  };
}

String _evidenceScopeLabel(L10n l10n, AiSeminarEvidenceScope scope) {
  return switch (scope) {
    AiSeminarEvidenceScope.currentChapter =>
      l10n.seminarEvidenceScopeCurrentChapter,
    AiSeminarEvidenceScope.currentBook => l10n.seminarEvidenceScopeCurrentBook,
    AiSeminarEvidenceScope.library => l10n.seminarEvidenceScopeLibrary,
    AiSeminarEvidenceScope.notes => l10n.seminarEvidenceScopeNotes,
    AiSeminarEvidenceScope.memory => l10n.seminarEvidenceScopeMemory,
    AiSeminarEvidenceScope.conceptGraph =>
      l10n.seminarEvidenceScopeConceptGraph,
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
