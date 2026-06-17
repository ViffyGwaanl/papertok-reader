part of '../../ai_chat_stream.dart';

class _SeminarRunConfig {
  const _SeminarRunConfig({
    required this.includeVerifier,
    required this.maxRounds,
    required this.roleProfiles,
  });

  final bool includeVerifier;
  final int maxRounds;
  final List<AiSeminarRoleProfile> roleProfiles;
}

class _SeminarRunSetupSheet extends StatefulWidget {
  const _SeminarRunSetupSheet({
    required this.initialQuestion,
    required this.cancelLabel,
    required this.startLabel,
    required this.onStart,
  });

  final String initialQuestion;
  final String cancelLabel;
  final String startLabel;
  final void Function(String question, _SeminarRunConfig config) onStart;

  @override
  State<_SeminarRunSetupSheet> createState() => _SeminarRunSetupSheetState();
}

class _SeminarRunSetupSheetState extends State<_SeminarRunSetupSheet> {
  late final TextEditingController _questionController;
  late final TextEditingController _maxRoundsController;
  late final Map<AiSeminarRole, TextEditingController> _promptControllers;
  late final Map<AiSeminarRole, TextEditingController> _nameControllers;
  late final Map<AiSeminarRole, AiSeminarRoleProfile?> _baseProfiles;
  late final Map<AiSeminarRole, bool> _roleEnabled;
  late final Map<AiSeminarRole, Set<AiSeminarEvidenceScope>>
      _roleEvidenceScopes;
  late final Set<AiSeminarRole> _roleEvidenceScopeTouched;
  late bool _includeVerifier;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.initialQuestion);
    _maxRoundsController = TextEditingController(
      text: Prefs().aiSeminarDefaultMaxRounds.toString(),
    );
    _includeVerifier = Prefs().aiSeminarIncludeVerifier;
    _baseProfiles = {
      for (final role in AiSeminarRole.values)
        role: Prefs().aiSeminarRoleProfileFor(role),
    };
    _promptControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: _baseProfiles[role]?.customPrompt ?? '',
        ),
    };
    _nameControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: _baseProfiles[role]?.name ?? '',
        ),
    };
    _roleEnabled = {
      for (final role in AiSeminarRole.values)
        role: _baseProfiles[role]?.enabled ?? true,
    };
    _roleEvidenceScopes = {
      for (final role in AiSeminarRole.values)
        role: {
          ...(_baseProfiles[role]?.evidenceScopes ??
              const <AiSeminarEvidenceScope>[]),
        },
    };
    _roleEvidenceScopeTouched = <AiSeminarRole>{};
  }

  @override
  void dispose() {
    _questionController.dispose();
    _maxRoundsController.dispose();
    for (final controller in _promptControllers.values) {
      controller.dispose();
    }
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final roleOrder = [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
      AiSeminarRole.verifier,
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            zh
                ? '这次配置只影响即将开始的研讨，不会覆盖全局设置。'
                : 'These settings only affect the next Seminar run.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: zh ? '研讨问题' : 'Seminar question',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('seminar-run-max-rounds'),
            controller: _maxRoundsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: zh ? '最多讨论轮次' : 'Max discussion rounds',
              helperText: zh
                  ? '出现分歧时可刷新证据再讨论，范围 1-5。'
                  : 'When disagreements appear, evidence can refresh and the Seminar can continue in chat. Range 1-5.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.verified_outlined),
            title: Text(zh ? '加入核验者' : 'Include verifier'),
            subtitle: Text(zh
                ? '让一个角色专门检查证据和引用。'
                : 'Adds a role focused on evidence checks.'),
            value: _includeVerifier,
            onChanged: (value) => setState(() => _includeVerifier = value),
          ),
          const SizedBox(height: 6),
          for (final role in roleOrder)
            _SeminarRunRoleProfileTile(
              role: role,
              initiallyExpanded: role == AiSeminarRole.critical,
              enabled: _roleEnabled[role] ?? true,
              nameController: _nameControllers[role]!,
              promptController: _promptControllers[role]!,
              evidenceScopes:
                  _roleEvidenceScopes[role] ?? const <AiSeminarEvidenceScope>{},
              onEnabledChanged: (value) {
                setState(() => _roleEnabled[role] = value);
              },
              onEvidenceScopeToggled: (scope) {
                setState(() {
                  _roleEvidenceScopeTouched.add(role);
                  final scopes = _roleEvidenceScopes.putIfAbsent(
                    role,
                    () => <AiSeminarEvidenceScope>{},
                  );
                  if (scopes.contains(scope)) {
                    scopes.remove(scope);
                  } else {
                    scopes.add(scope);
                  }
                });
              },
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(widget.cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('seminar-run-start'),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: Text(widget.startLabel),
                  onPressed: _start,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _start() {
    final maxRounds = int.tryParse(_maxRoundsController.text.trim()) ??
        Prefs().aiSeminarDefaultMaxRounds;
    final profiles = <AiSeminarRoleProfile>[];
    for (final role in AiSeminarRole.values) {
      final baseProfile = _baseProfiles[role];
      final selectedScopes =
          _roleEvidenceScopes[role] ?? const <AiSeminarEvidenceScope>{};
      final evidenceScopes =
          selectedScopes.isEmpty && _roleEvidenceScopeTouched.contains(role)
              ? const <AiSeminarEvidenceScope>[
                  AiSeminarEvidenceScope.currentBook,
                ]
              : selectedScopes.toList(growable: false);
      final profile = AiSeminarRoleProfile(
        role: role,
        name: _nameControllers[role]?.text,
        customPrompt: _promptControllers[role]?.text,
        enabled: _roleEnabled[role] ?? true,
        evidenceScopes: evidenceScopes,
        allowedToolIds: baseProfile?.allowedToolIds ?? const <String>[],
      );
      if (profile.hasOverrides) {
        profiles.add(profile);
      }
    }
    widget.onStart(
      _questionController.text,
      _SeminarRunConfig(
        includeVerifier: _includeVerifier,
        maxRounds: maxRounds.clamp(1, 10).toInt(),
        roleProfiles: List.unmodifiable(profiles),
      ),
    );
  }
}

class _SeminarRunRoleProfileTile extends StatelessWidget {
  const _SeminarRunRoleProfileTile({
    required this.role,
    required this.initiallyExpanded,
    required this.enabled,
    required this.nameController,
    required this.promptController,
    required this.evidenceScopes,
    required this.onEnabledChanged,
    required this.onEvidenceScopeToggled,
  });

  final AiSeminarRole role;
  final bool initiallyExpanded;
  final bool enabled;
  final TextEditingController nameController;
  final TextEditingController promptController;
  final Set<AiSeminarEvidenceScope> evidenceScopes;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<AiSeminarEvidenceScope> onEvidenceScopeToggled;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final label = _seminarRunRoleLabel(context, role);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ClaudePalette.divider(context)),
        ),
      ),
      child: ExpansionTile(
        key: ValueKey('seminar-run-role-${role.asString}'),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(label),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(zh ? '启用$label' : 'Enable $label'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: zh ? '$label名称' : '$label name',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('seminar-run-role-${role.asString}-prompt'),
            controller: promptController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: zh ? '$label提示词' : '$label prompt',
              hintText: zh
                  ? '例如：先列出你不同意的论点，再说明需要哪些证据。'
                  : 'Example: list what you disagree with first, then name the evidence needed.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              zh ? '本次证据范围' : 'Run evidence scope',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in _nativeSeminarRunEvidenceScopeOptions)
                _SeminarRunEvidenceScopeChip(
                  key: ValueKey(
                    'seminar-run-role-${role.asString}-scope-'
                    '${scope.asString}',
                  ),
                  label: _nativeSeminarEvidenceScopeLabel(context, scope),
                  selected: scope == AiSeminarEvidenceScope.currentBook
                      ? evidenceScopes.isEmpty || evidenceScopes.contains(scope)
                      : evidenceScopes.contains(scope),
                  onPressed: () => onEvidenceScopeToggled(scope),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

const _nativeSeminarRunEvidenceScopeOptions = <AiSeminarEvidenceScope>[
  AiSeminarEvidenceScope.currentBook,
  AiSeminarEvidenceScope.library,
  AiSeminarEvidenceScope.notes,
  AiSeminarEvidenceScope.memory,
  AiSeminarEvidenceScope.conceptGraph,
];

String _nativeSeminarEvidenceScopeLabel(
  BuildContext context,
  AiSeminarEvidenceScope scope,
) {
  final l10n = L10n.of(context);
  switch (scope) {
    case AiSeminarEvidenceScope.currentChapter:
      return l10n.seminarEvidenceScopeCurrentChapter;
    case AiSeminarEvidenceScope.currentBook:
      return l10n.seminarEvidenceScopeCurrentBook;
    case AiSeminarEvidenceScope.library:
      return l10n.seminarEvidenceScopeLibrary;
    case AiSeminarEvidenceScope.notes:
      return l10n.seminarEvidenceScopeNotes;
    case AiSeminarEvidenceScope.memory:
      return l10n.seminarEvidenceScopeMemory;
    case AiSeminarEvidenceScope.conceptGraph:
      return l10n.seminarEvidenceScopeConceptGraph;
  }
}

class _SeminarRunEvidenceScopeChip extends StatelessWidget {
  const _SeminarRunEvidenceScopeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
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

String _seminarRunRoleLabel(BuildContext context, AiSeminarRole role) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (role) {
    AiSeminarRole.critical => zh ? '批判者' : 'Critical',
    AiSeminarRole.supportive => zh ? '支持者' : 'Supportive',
    AiSeminarRole.synthesizer => zh ? '综合者' : 'Synthesizer',
    AiSeminarRole.verifier => zh ? '核验者' : 'Verifier',
  };
}
