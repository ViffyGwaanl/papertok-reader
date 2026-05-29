import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class CustomSkillsPage extends StatefulWidget {
  const CustomSkillsPage({super.key});

  @override
  State<CustomSkillsPage> createState() => _CustomSkillsPageState();
}

class _CustomSkillsPageState extends State<CustomSkillsPage> {
  final _store = CustomSkillStore();
  final _controller = TextEditingController();
  List<CustomSkillContract> _contracts = const <CustomSkillContract>[];
  List<String> _errors = const <String>[];
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reload() {
    _contracts = _store.contracts();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Custom skills',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Import governed JSON skills. Accepted skills can add prompt behavior and only use the read-only tools declared in the contract.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Skill JSON',
              hintText: '{ "schemaVersion": 1, ... }',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('Paste safe example'),
                onPressed: _pasteSafeExample,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import skill'),
                onPressed: _importSkill,
              ),
            ],
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ErrorPanel(errors: _errors),
          ] else if (_imported) ...[
            const SizedBox(height: 12),
            const _SuccessPanel(),
          ],
          const SizedBox(height: 24),
          Text(
            'Installed skills',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_contracts.isEmpty)
            const _EmptySkills()
          else
            ..._contracts.map(
              (contract) => _CustomSkillTile(
                contract: contract,
                onEnabledChanged: (enabled) async {
                  await _store.setEnabled(contract.id, enabled);
                  if (!mounted) return;
                  setState(_reload);
                },
                onDelete: () async {
                  await _store.delete(contract.id);
                  if (!mounted) return;
                  setState(_reload);
                },
              ),
            ),
        ],
      ),
    );
  }

  void _pasteSafeExample() {
    _controller.text = _safeExampleJson;
    setState(() {
      _errors = const <String>[];
      _imported = false;
    });
  }

  Future<void> _importSkill() async {
    final result = await _store.importJson(_controller.text);
    if (!mounted) return;
    setState(() {
      _errors = result.errors;
      _imported = result.accepted;
      _reload();
    });
  }
}

class _CustomSkillTile extends StatelessWidget {
  const _CustomSkillTile({
    required this.contract,
    required this.onEnabledChanged,
    required this.onDelete,
  });

  final CustomSkillContract contract;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final runtimeReady =
        contract.canInject(AiToolPermissionMatrix.defaultMatrix);
    final toolNames = contract.allowedToolIds.isEmpty
        ? 'No tools'
        : contract.allowedToolIds
            .map((id) => AiToolRegistry.displayNameForId(id))
            .join(', ');
    final sceneNames =
        contract.scenes.map((scene) => scene.asString).join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(
          runtimeReady
              ? Icons.extension_outlined
              : Icons.extension_off_outlined,
        ),
        title: Text(contract.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contract.id),
            if ((contract.description ?? '').isNotEmpty)
              Text(contract.description!),
            Text('Scenes: $sceneNames'),
            Text('Tools: $toolNames'),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(runtimeReady ? 'Runtime ready' : 'Disabled'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Switch.adaptive(
              value: contract.enabled,
              onChanged: onEnabledChanged,
            ),
            IconButton(
              tooltip: 'Delete skill',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import blocked',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 6),
            for (final error in errors)
              Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Skill imported. Enable it from Active Skill before chatting.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _EmptySkills extends StatelessWidget {
  const _EmptySkills();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No custom skills yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ClaudePalette.secondary(context),
            ),
      ),
    );
  }
}

const _safeExampleJson = '''
{
  "schemaVersion": 1,
  "id": "slow_reader",
  "name": "Slow Reader",
  "description": "Explain one passage with local evidence.",
  "systemPromptAppend": "Move slowly. Use current-book evidence and name uncertainty before making a claim.",
  "allowedToolIds": ["current_chapter_content", "resolve_cfi"],
  "scenes": ["reading"],
  "enabled": true
}
''';
