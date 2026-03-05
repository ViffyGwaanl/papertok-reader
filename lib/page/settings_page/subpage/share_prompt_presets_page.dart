import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/share_prompt_preset.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:flutter/material.dart';

class SharePromptPresetsPage extends StatefulWidget {
  const SharePromptPresetsPage({super.key});

  static const routeName = '/settings/share_prompt_presets';

  @override
  State<SharePromptPresetsPage> createState() => _SharePromptPresetsPageState();
}

class _SharePromptPresetsPageState extends State<SharePromptPresetsPage> {
  SharePromptPresetsState get _state => Prefs().sharePromptPresetsStateV2;

  Future<void> _save(SharePromptPresetsState next) async {
    Prefs().sharePromptPresetsStateV2 = next;
    setState(() {});
  }

  Future<void> _editPreset({SharePromptPreset? preset}) async {
    final l10n = L10n.of(context);

    final now = DateTime.now().millisecondsSinceEpoch;
    final isNew = preset == null;

    final titleCtrl = TextEditingController(text: preset?.title ?? '');
    final promptCtrl = TextEditingController(text: preset?.prompt ?? '');
    bool enabled = preset?.enabled ?? true;

    final result = await showDialog<SharePromptPreset>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(isNew
                  ? l10n.settingsSharePromptPresetAdd
                  : l10n.settingsSharePromptPresetEdit),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.settingsSharePromptPresetTitle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: promptCtrl,
                      maxLines: 8,
                      minLines: 3,
                      decoration: InputDecoration(
                        labelText: l10n.settingsSharePromptPresetPrompt,
                        hintText: l10n.settingsSharePanelPromptHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: enabled,
                      onChanged: (v) => setLocal(() => enabled = v),
                      title: Text(l10n.settingsSharePromptPresetEnabled),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.commonCancel),
                ),
                TextButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    final prompt = promptCtrl.text.trim();
                    if (title.isEmpty || prompt.isEmpty) {
                      // Keep it simple for now.
                      return;
                    }
                    final id = preset?.id ?? 'custom_${now}_${title.hashCode}';
                    Navigator.of(ctx).pop(
                      SharePromptPreset(
                        id: id,
                        title: title,
                        prompt: prompt,
                        enabled: enabled,
                        createdAtMs: preset?.createdAtMs ?? now,
                        updatedAtMs: now,
                        isBuiltin: preset?.isBuiltin ?? false,
                      ),
                    );
                  },
                  child: Text(l10n.commonSave),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final presets = [..._state.presets];
    final idx = presets.indexWhere((p) => p.id == result.id);
    if (idx >= 0) {
      presets[idx] = result;
    } else {
      presets.add(result);
    }

    await _save(
      SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: presets,
        lastSelectedPresetId: _state.lastSelectedPresetId,
      ),
    );
  }

  Future<void> _deletePreset(SharePromptPreset preset) async {
    final l10n = L10n.of(context);

    if (preset.isBuiltin) {
      // For builtin presets we just disable.
      final presets = _state.presets
          .map((p) => p.id == preset.id ? p.copyWith(enabled: false) : p)
          .toList();
      await _save(
        SharePromptPresetsState(
          schemaVersion: SharePromptPresetsState.currentSchemaVersion,
          presets: presets,
          lastSelectedPresetId: _state.lastSelectedPresetId,
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.commonDelete),
          content: Text(l10n.settingsSharePromptPresetDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final presets = _state.presets.where((p) => p.id != preset.id).toList();
    await _save(
      SharePromptPresetsState(
        schemaVersion: SharePromptPresetsState.currentSchemaVersion,
        presets: presets,
        lastSelectedPresetId: _state.lastSelectedPresetId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final presets = [..._state.presets];

    return SettingsSubpageScaffold(
      title: l10n.settingsSharePromptPresetsTitle,
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              itemCount: presets.length,
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex -= 1;
                final next = [...presets];
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                await _save(
                  SharePromptPresetsState(
                    schemaVersion: SharePromptPresetsState.currentSchemaVersion,
                    presets: next,
                    lastSelectedPresetId: _state.lastSelectedPresetId,
                  ),
                );
              },
              itemBuilder: (ctx, i) {
                final p = presets[i];
                final preview = p.prompt.trim().split('\n').first;

                return ListTile(
                  key: ValueKey(p.id),
                  title: Text(p.title),
                  subtitle: Text(preview),
                  leading: Switch.adaptive(
                    value: p.enabled,
                    onChanged: (v) async {
                      final next = presets
                          .map((x) => x.id == p.id
                              ? x.copyWith(
                                  enabled: v,
                                  updatedAtMs:
                                      DateTime.now().millisecondsSinceEpoch,
                                )
                              : x)
                          .toList();
                      await _save(
                        SharePromptPresetsState(
                          schemaVersion:
                              SharePromptPresetsState.currentSchemaVersion,
                          presets: next,
                          lastSelectedPresetId: _state.lastSelectedPresetId,
                        ),
                      );
                    },
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.commonEdit,
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editPreset(preset: p),
                      ),
                      IconButton(
                        tooltip: l10n.commonDelete,
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deletePreset(p),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _editPreset(),
                icon: const Icon(Icons.add),
                label: Text(l10n.settingsSharePromptPresetAdd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
