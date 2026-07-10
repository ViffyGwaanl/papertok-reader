import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/ai_library_index_page.dart';
import 'package:papertok_reader/page/settings_page/ai_quick_prompts_editor.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_tools.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/page/settings_page/developer/vibration_test_page.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/subpage/log_page.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/page/settings_page/subpage/share_inbox_diagnostics_page.dart';
import 'package:papertok_reader/widgets/settings/settings_section_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (context) => page),
    );
  }

  void _pushSubpage(BuildContext context, String title, Widget child) {
    _push(context, SettingsSubpageScaffold(title: title, child: child));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsSubpageScaffold(
      title: 'Developer Options',
      child: AnimatedBuilder(
        animation: Prefs(),
        builder: (context, _) {
          final enabled = Prefs().developerOptionsEnabled;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              SettingsSectionCard(
                title: 'General',
                tiles: [
                  _SwitchTile(
                    icon: Icons.developer_mode_outlined,
                    title: 'Enable Developer Options',
                    subtitle:
                        'Toggle off to hide developer entries in settings',
                    value: enabled,
                    onChanged: (value) {
                      Prefs().developerOptionsEnabled = value;
                      if (!value && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
              // E4 batch 3: geek-facing AI capabilities stowed here from the
              // first-level AI section / AI settings subpage. Entry moves
              // only — every page keeps working unchanged.
              SettingsSectionCard(
                title: 'AI',
                tiles: [
                  SettingsNavRow(
                    icon: Icons.handyman_outlined,
                    title: l10n.settingsAiTools,
                    onTap: () => _pushSubpage(context, l10n.settingsAiTools,
                        const AiToolsSettingsPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.storage_outlined,
                    title: l10n.settingsAiLibraryIndexTitle,
                    onTap: () => _push(context, const AiLibraryIndexPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.extension_outlined,
                    title: l10n.settingsAiCustomSkillsTitle,
                    onTap: () => _push(context, const CustomSkillsPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.bolt_outlined,
                    title: l10n.settingsAiQuickPrompts,
                    onTap: () => _push(context, const AiQuickPromptsEditor()),
                  ),
                  SettingsNavRow(
                    icon: Icons.tune_outlined,
                    title: l10n.seminarConfigTitle,
                    onTap: () => _push(context, const AiSeminarConfigPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.account_tree_outlined,
                    title: l10n.conceptGraphTitle,
                    onTap: () =>
                        _push(context, const ConceptGraphExplorerPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.ios_share_outlined,
                    title: l10n.knowledgeExportTitle,
                    onTap: () =>
                        _push(context, const KnowledgeAssetExportPage()),
                  ),
                ],
              ),
              SettingsSectionCard(
                title: 'Diagnostics',
                tiles: [
                  SettingsNavRow(
                    icon: Icons.article_outlined,
                    title: l10n.settingsAdvancedLog,
                    onTap: () => _push(context, const LogPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.inbox_outlined,
                    title: l10n.settingsShareInboxDiagnosticsTitle,
                    onTap: () =>
                        _push(context, const ShareInboxDiagnosticsPage()),
                  ),
                  SettingsNavRow(
                    icon: Icons.vibration_outlined,
                    title: 'Vibration Test',
                    subtitle: 'Inspect device support and trigger presets',
                    onTap: () => _push(context, const VibrationTestPage()),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
