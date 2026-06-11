import 'package:flutter/material.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class AiSeminarConfigPage extends StatefulWidget {
  const AiSeminarConfigPage({super.key});

  @override
  State<AiSeminarConfigPage> createState() => _AiSeminarConfigPageState();
}

class _AiSeminarConfigPageState extends State<AiSeminarConfigPage> {
  late final TextEditingController _maxRoundsController;
  late final TextEditingController _roleOutputBudgetController;
  late final TextEditingController _runBudgetController;
  late final TextEditingController _runCostCapController;
  late final Map<AiSeminarRole, TextEditingController> _roleNameControllers;
  late final Map<AiSeminarRole, TextEditingController> _rolePromptControllers;
  late final Map<AiSeminarRole, bool> _roleEnabled;
  late final Map<AiSeminarRole, Set<AiSeminarEvidenceScope>>
      _roleEvidenceScopes;
  late final Map<AiSeminarRole, Set<String>> _roleAllowedToolIds;
  late bool _includeVerifier;

  @override
  void initState() {
    super.initState();
    _includeVerifier = Prefs().aiSeminarIncludeVerifier;
    _maxRoundsController = TextEditingController(
      text: Prefs().aiSeminarDefaultMaxRounds.toString(),
    );
    _roleOutputBudgetController = TextEditingController(
      text: Prefs().aiSeminarDefaultRoleOutputTokenBudget?.toString() ?? '',
    );
    _runBudgetController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunTokenBudget?.toString() ?? '',
    );
    _runCostCapController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunCostCapUsd?.toString() ?? '',
    );
    _roleNameControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: Prefs().aiSeminarRoleProfileFor(role)?.name ?? '',
        ),
    };
    _rolePromptControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: Prefs().aiSeminarRoleProfileFor(role)?.customPrompt ?? '',
        ),
    };
    _roleEnabled = {
      for (final role in AiSeminarRole.values)
        role: Prefs().aiSeminarRoleProfileFor(role)?.enabled ?? true,
    };
    _roleEvidenceScopes = {
      for (final role in AiSeminarRole.values)
        role: {
          ...?Prefs().aiSeminarRoleProfileFor(role)?.evidenceScopes,
        },
    };
    _roleAllowedToolIds = {
      for (final role in AiSeminarRole.values)
        role: {
          ...?Prefs().aiSeminarRoleProfileFor(role)?.allowedToolIds,
        },
    };
  }

  @override
  void dispose() {
    _maxRoundsController.dispose();
    _roleOutputBudgetController.dispose();
    _runBudgetController.dispose();
    _runCostCapController.dispose();
    for (final controller in _roleNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _rolePromptControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsSubpageScaffold(
      title: l10n.seminarConfigTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ConfigSection(
            title: l10n.seminarConfigArchitectureTitle,
            icon: Icons.account_tree_outlined,
            children: [
              Text(
                l10n.seminarConfigArchitectureDesc,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.seminarAgentRolesFixed,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ConfigSection(
            title: l10n.seminarConfigDefaultsTitle,
            icon: Icons.tune_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.verified_outlined),
                title: Text(l10n.seminarRoleVerifier),
                subtitle: Text(l10n.seminarVerifierDesc),
                value: _includeVerifier,
                onChanged: (value) {
                  setState(() => _includeVerifier = value);
                  Prefs().aiSeminarIncludeVerifier = value;
                },
              ),
              const SizedBox(height: 8),
              _DefaultBudgetFields(
                maxRoundsController: _maxRoundsController,
                roleOutputBudgetController: _roleOutputBudgetController,
                runBudgetController: _runBudgetController,
                runCostCapController: _runCostCapController,
                onMaxRoundsChanged: (value) {
                  Prefs().aiSeminarDefaultMaxRounds =
                      (_positiveIntOrNull(value) ?? 2).clamp(1, 5).toInt();
                },
                onRoleOutputChanged: (value) {
                  Prefs().aiSeminarDefaultRoleOutputTokenBudget =
                      _positiveIntOrNull(value);
                },
                onRunBudgetChanged: (value) {
                  Prefs().aiSeminarDefaultRunTokenBudget =
                      _positiveIntOrNull(value);
                },
                onRunCostCapChanged: (value) {
                  Prefs().aiSeminarDefaultRunCostCapUsd =
                      _positiveDoubleOrNull(value);
                },
              ),
              const SizedBox(height: 8),
              Text(
                l10n.seminarConfigDefaultsDesc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ConfigSection(
            title: _configText(
              context,
              en: 'Role prompt profiles',
              zh: '角色提示词设置',
            ),
            icon: Icons.badge_outlined,
            children: [
              Text(
                _configText(
                  context,
                  en: 'Customize each Seminar role name and prompt while keeping evidence and Review approval gates enforced. Do not paste API keys or credentials into role prompts.',
                  zh: '可以自定义每个研讨角色的名称和提示词；证据引用和 Review 审批边界仍由系统强制执行。不要把 API key 或密钥写进角色提示词。',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
              const SizedBox(height: 8),
              for (final role in AiSeminarRole.values)
                _RoleProfileFields(
                  role: role,
                  nameController: _roleNameControllers[role]!,
                  promptController: _rolePromptControllers[role]!,
                  enabled: _roleEnabled[role] ?? true,
                  selectedEvidenceScopes: _roleEvidenceScopes[role] ?? const {},
                  selectedToolIds: _roleAllowedToolIds[role] ?? const {},
                  onEnabledChanged: (value) {
                    setState(() => _roleEnabled[role] = value);
                    _saveRoleProfile(role);
                  },
                  onEvidenceScopeChanged: (scope, selected) {
                    setState(() {
                      final scopes = _roleEvidenceScopes.putIfAbsent(
                        role,
                        () => <AiSeminarEvidenceScope>{},
                      );
                      if (selected) {
                        scopes.add(scope);
                      } else {
                        scopes.remove(scope);
                      }
                    });
                    _saveRoleProfile(role);
                  },
                  onToolChanged: (toolId, selected) {
                    setState(() {
                      final toolIds = _roleAllowedToolIds.putIfAbsent(
                        role,
                        () => <String>{},
                      );
                      if (selected) {
                        toolIds.add(toolId);
                      } else {
                        toolIds.remove(toolId);
                      }
                    });
                    _saveRoleProfile(role);
                  },
                  onChanged: () => _saveRoleProfile(role),
                ),
            ],
          ),
        ],
      ),
    );
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

  void _saveRoleProfile(AiSeminarRole role) {
    Prefs().setAiSeminarRoleProfile(
      role,
      name: _roleNameControllers[role]?.text,
      customPrompt: _rolePromptControllers[role]?.text,
      enabled: _roleEnabled[role] ?? true,
      evidenceScopes:
          (_roleEvidenceScopes[role] ?? const <AiSeminarEvidenceScope>{})
              .toList(growable: false),
      allowedToolIds: (_roleAllowedToolIds[role] ?? const <String>{}).toList(
        growable: false,
      ),
    );
  }
}

class _RoleProfileFields extends StatelessWidget {
  const _RoleProfileFields({
    required this.role,
    required this.nameController,
    required this.promptController,
    required this.enabled,
    required this.selectedEvidenceScopes,
    required this.selectedToolIds,
    required this.onEnabledChanged,
    required this.onEvidenceScopeChanged,
    required this.onToolChanged,
    required this.onChanged,
  });

  final AiSeminarRole role;
  final TextEditingController nameController;
  final TextEditingController promptController;
  final bool enabled;
  final Set<AiSeminarEvidenceScope> selectedEvidenceScopes;
  final Set<String> selectedToolIds;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(AiSeminarEvidenceScope scope, bool selected)
      onEvidenceScopeChanged;
  final void Function(String toolId, bool selected) onToolChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleProfileLabel(context, role);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: role == AiSeminarRole.critical,
        title: Text(roleLabel),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SwitchListTile(
            key: ValueKey('seminar-role-${role.asString}-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(_configText(
              context,
              en: 'Enable $roleLabel',
              zh: '启用$roleLabel',
            )),
            subtitle: Text(_configText(
              context,
              en: 'Disabled roles stay in saved settings but are skipped in new Seminar runs.',
              zh: '关闭后设置仍会保留，但新的研讨不会执行该角色。',
            )),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: _configText(
                context,
                en: '$roleLabel role name',
                zh: '$roleLabel角色名称',
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: promptController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: _configText(
                context,
                en: '$roleLabel custom prompt',
                zh: '$roleLabel自定义提示词',
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          _RoleEvidenceScopePicker(
            role: role,
            selectedScopes: selectedEvidenceScopes,
            onChanged: onEvidenceScopeChanged,
          ),
          const SizedBox(height: 8),
          _RoleToolPicker(
            role: role,
            selectedToolIds: selectedToolIds,
            onChanged: onToolChanged,
          ),
        ],
      ),
    );
  }
}

class _RoleEvidenceScopePicker extends StatelessWidget {
  const _RoleEvidenceScopePicker({
    required this.role,
    required this.selectedScopes,
    required this.onChanged,
  });

  final AiSeminarRole role;
  final Set<AiSeminarEvidenceScope> selectedScopes;
  final void Function(AiSeminarEvidenceScope scope, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    const scopes = [
      AiSeminarEvidenceScope.currentBook,
      AiSeminarEvidenceScope.library,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _configText(
            context,
            en: 'Session evidence hints',
            zh: '会话证据提示',
          ),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(
          _configText(
            context,
            en: 'These add sources to the Seminar evidence bundle. They do not filter evidence separately for each role yet.',
            zh: '这些选项会为整场研讨补充证据来源，目前还不会按角色单独过滤证据。',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
        for (final scope in scopes)
          CheckboxListTile(
            key: ValueKey(
              'seminar-role-${role.asString}-scope-${scope.asString}',
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_evidenceScopeLabel(context, scope)),
            value: selectedScopes.contains(scope),
            onChanged: (value) => onChanged(scope, value == true),
          ),
      ],
    );
  }
}

class _RoleToolPicker extends StatelessWidget {
  const _RoleToolPicker({
    required this.role,
    required this.selectedToolIds,
    required this.onChanged,
  });

  static const _toolIds = [
    'semantic_search_current_book',
    'semantic_search_library',
    'notes_search',
    'memory_search',
    'concept_graph_search',
    'resolve_cfi',
  ];

  final AiSeminarRole role;
  final Set<String> selectedToolIds;
  final void Function(String toolId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _configText(
            context,
            en: 'Allowed read-only tools',
            zh: '允许的只读工具',
          ),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(
          _configText(
            context,
            en: 'Write tools, web tools, and recursive sub-agent tools are filtered out even if they appear in imported settings.',
            zh: '写入工具、联网工具和递归 sub-agent 工具即使出现在导入设置里也会被过滤。',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
        for (final toolId in _toolIds)
          CheckboxListTile(
            key: ValueKey('seminar-role-${role.asString}-tool-$toolId'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_seminarToolLabel(context, toolId)),
            value: selectedToolIds.contains(toolId),
            onChanged: (value) => onChanged(toolId, value == true),
          ),
      ],
    );
  }
}

class _DefaultBudgetFields extends StatelessWidget {
  const _DefaultBudgetFields({
    required this.maxRoundsController,
    required this.roleOutputBudgetController,
    required this.runBudgetController,
    required this.runCostCapController,
    required this.onMaxRoundsChanged,
    required this.onRoleOutputChanged,
    required this.onRunBudgetChanged,
    required this.onRunCostCapChanged,
  });

  final TextEditingController maxRoundsController;
  final TextEditingController roleOutputBudgetController;
  final TextEditingController runBudgetController;
  final TextEditingController runCostCapController;
  final ValueChanged<String> onMaxRoundsChanged;
  final ValueChanged<String> onRoleOutputChanged;
  final ValueChanged<String> onRunBudgetChanged;
  final ValueChanged<String> onRunCostCapChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final fields = <Widget>[
          TextField(
            key: const ValueKey('seminar-default-max-rounds'),
            controller: maxRoundsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.seminarDefaultMaxRounds,
              helperText: l10n.seminarDefaultMaxRoundsHelper,
              border: const OutlineInputBorder(),
            ),
            onChanged: onMaxRoundsChanged,
          ),
          TextField(
            controller: roleOutputBudgetController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.seminarRoleOutputBudget,
              border: const OutlineInputBorder(),
            ),
            onChanged: onRoleOutputChanged,
          ),
          TextField(
            controller: runBudgetController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.seminarRunTokenBudget,
              border: const OutlineInputBorder(),
            ),
            onChanged: onRunBudgetChanged,
          ),
          TextField(
            controller: runCostCapController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.seminarRunCostCapUsd,
              border: const OutlineInputBorder(),
            ),
            onChanged: onRunCostCapChanged,
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
    );
  }
}

String _configText(
  BuildContext context, {
  required String en,
  required String zh,
}) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}

String _roleProfileLabel(BuildContext context, AiSeminarRole role) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (role) {
    AiSeminarRole.critical => zh ? '批判者' : 'Critical',
    AiSeminarRole.supportive => zh ? '支持者' : 'Supportive',
    AiSeminarRole.synthesizer => zh ? '综合者' : 'Synthesizer',
    AiSeminarRole.verifier => zh ? '核验者' : 'Verifier',
  };
}

String _seminarToolLabel(BuildContext context, String toolId) {
  return switch (toolId.trim()) {
    'semantic_search_current_book' => _configText(
        context,
        en: 'Current-book semantic search',
        zh: '书内语义检索',
      ),
    'semantic_search_library' => _configText(
        context,
        en: 'Library semantic search',
        zh: '书库语义检索',
      ),
    'notes_search' => _configText(
        context,
        en: 'Notes search',
        zh: '笔记搜索',
      ),
    'memory_search' => _configText(
        context,
        en: 'Memory search',
        zh: '记忆搜索',
      ),
    'concept_graph_search' => _configText(
        context,
        en: 'Concept graph search',
        zh: '图谱检索',
      ),
    'resolve_cfi' => _configText(
        context,
        en: 'Source resolver',
        zh: '原文定位',
      ),
    _ => toolId.trim().isNotEmpty
        ? toolId.trim()
        : _configText(
            context,
            en: 'Read-only tool',
            zh: '只读工具',
          ),
  };
}

String _evidenceScopeLabel(
  BuildContext context,
  AiSeminarEvidenceScope scope,
) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (scope) {
    AiSeminarEvidenceScope.currentChapter =>
      zh ? '当前章节证据' : 'Current chapter evidence',
    AiSeminarEvidenceScope.currentBook =>
      zh ? '当前书证据' : 'Current book evidence',
    AiSeminarEvidenceScope.library => zh ? '书库证据' : 'Library evidence',
    AiSeminarEvidenceScope.notes => zh ? '笔记证据' : 'Notes evidence',
    AiSeminarEvidenceScope.memory => zh ? '记忆证据' : 'Memory evidence',
    AiSeminarEvidenceScope.conceptGraph =>
      zh ? '概念图谱证据' : 'Concept graph evidence',
  };
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
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
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
