import 'package:flutter/material.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class AiSeminarConfigPage extends StatefulWidget {
  const AiSeminarConfigPage({super.key});

  @override
  State<AiSeminarConfigPage> createState() => _AiSeminarConfigPageState();
}

class _AiSeminarConfigPageState extends State<AiSeminarConfigPage> {
  late final TextEditingController _roleOutputBudgetController;
  late final TextEditingController _runBudgetController;
  late final TextEditingController _runCostCapController;
  late bool _includeVerifier;

  @override
  void initState() {
    super.initState();
    _includeVerifier = Prefs().aiSeminarIncludeVerifier;
    _roleOutputBudgetController = TextEditingController(
      text: Prefs().aiSeminarDefaultRoleOutputTokenBudget?.toString() ?? '',
    );
    _runBudgetController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunTokenBudget?.toString() ?? '',
    );
    _runCostCapController = TextEditingController(
      text: Prefs().aiSeminarDefaultRunCostCapUsd?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _roleOutputBudgetController.dispose();
    _runBudgetController.dispose();
    _runCostCapController.dispose();
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
                roleOutputBudgetController: _roleOutputBudgetController,
                runBudgetController: _runBudgetController,
                runCostCapController: _runCostCapController,
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
}

class _DefaultBudgetFields extends StatelessWidget {
  const _DefaultBudgetFields({
    required this.roleOutputBudgetController,
    required this.runBudgetController,
    required this.runCostCapController,
    required this.onRoleOutputChanged,
    required this.onRunBudgetChanged,
    required this.onRunCostCapChanged,
  });

  final TextEditingController roleOutputBudgetController;
  final TextEditingController runBudgetController;
  final TextEditingController runCostCapController;
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
