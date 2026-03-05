import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/page/settings_page/subpage/share_prompt_presets_page.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

class ShareAndShortcutsPanelPage extends StatefulWidget {
  const ShareAndShortcutsPanelPage({super.key});

  static const String routeName = '/settings/share_and_shortcuts_panel';

  @override
  State<ShareAndShortcutsPanelPage> createState() =>
      _ShareAndShortcutsPanelPageState();
}

class _ShareAndShortcutsPanelPageState
    extends State<ShareAndShortcutsPanelPage> {
  String _ttlLabel(L10n l10n, int days) {
    if (days == 0) return l10n.settingsSharePanelTtlNever;
    return l10n.settingsSharePanelTtlDays(days);
  }

  Future<void> _pickTtlDays() async {
    final l10n = L10n.of(context);
    final current = Prefs().sharePanelTtlDaysV1;

    final options = <int>[1, 3, 7, 30, 0];

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsSharePanelTtlTitle),
          children: [
            for (final d in options)
              RadioListTile<int>(
                value: d,
                groupValue: current,
                title: Text(_ttlLabel(l10n, d)),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().sharePanelTtlDaysV1 = picked;
      setState(() {});
    }
  }

  Future<void> _pickSharePanelMode() async {
    final l10n = L10n.of(context);
    final current = Prefs().sharePanelModeV1;

    String label(String v) {
      switch (v) {
        case Prefs.sharePanelModeAuto:
          return l10n.settingsSharePanelModeAuto;
        case Prefs.sharePanelModeAiChat:
          return l10n.settingsSharePanelModeAiChat;
        case Prefs.sharePanelModeBookshelf:
          return l10n.settingsSharePanelModeBookshelf;
        case Prefs.sharePanelModeAsk:
          return l10n.settingsSharePanelModeAsk;
        default:
          return v;
      }
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsSharePanelModeTitle),
          children: [
            for (final v in const [
              Prefs.sharePanelModeAuto,
              Prefs.sharePanelModeAiChat,
              Prefs.sharePanelModeBookshelf,
              Prefs.sharePanelModeAsk,
            ])
              RadioListTile<String>(
                value: v,
                groupValue: current,
                title: Text(label(v)),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().sharePanelModeV1 = picked;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    if (!AnxPlatform.isIOS) {
      return SettingsSubpageScaffold(
        title: l10n.settingsShareAndShortcutsPanel,
        child: const Center(child: Text('Not supported on this platform.')),
      );
    }

    String shareModeLabel(String v) {
      switch (v) {
        case Prefs.sharePanelModeAuto:
          return l10n.settingsSharePanelModeAuto;
        case Prefs.sharePanelModeAiChat:
          return l10n.settingsSharePanelModeAiChat;
        case Prefs.sharePanelModeBookshelf:
          return l10n.settingsSharePanelModeBookshelf;
        case Prefs.sharePanelModeAsk:
          return l10n.settingsSharePanelModeAsk;
        default:
          return v;
      }
    }

    return SettingsSubpageScaffold(
      title: l10n.settingsShareAndShortcutsPanel,
      child: Column(
        children: [
          SettingsSection(
            title: Text(l10n.settingsSharePanelSectionTitle),
            tiles: [
              SettingsTile.navigation(
                title: Text(l10n.settingsSharePanelModeTitle),
                description: Text(l10n.settingsSharePanelModeDesc),
                trailing: Text(shareModeLabel(Prefs().sharePanelModeV1)),
                onPressed: (_) => _pickSharePanelMode(),
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsSharePromptPresetsTitle),
                description: Text(l10n.settingsSharePromptPresetsDesc),
                onPressed: (_) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SharePromptPresetsPage(),
                    ),
                  );
                },
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsSharePanelTtlTitle),
                description: Text(l10n.settingsSharePanelTtlDesc),
                trailing: Text(_ttlLabel(l10n, Prefs().sharePanelTtlDaysV1)),
                onPressed: (_) => _pickTtlDays(),
              ),
              SettingsTile.switchTile(
                initialValue: Prefs().sharePanelCleanupAfterUseV1,
                onToggle: (value) {
                  Prefs().sharePanelCleanupAfterUseV1 = value;
                  setState(() {});
                },
                title: Text(l10n.settingsSharePanelCleanupAfterUse),
                description: Text(l10n.settingsSharePanelCleanupAfterUseDesc),
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsShortcutsSectionTitle),
            tiles: [
              SettingsTile.switchTile(
                initialValue: Prefs().shortcutsSendMessageOpenAppDefaultV1,
                onToggle: (value) {
                  Prefs().shortcutsSendMessageOpenAppDefaultV1 = value;
                  setState(() {});
                },
                title: Text(l10n.settingsShortcutsSendMessageOpenAppDefault),
                description:
                    Text(l10n.settingsShortcutsSendMessageOpenAppDefaultDesc),
              ),
              SettingsTile.switchTile(
                initialValue: Prefs().shortcutsSendMessageShowDialogDefaultV1,
                onToggle: (value) {
                  Prefs().shortcutsSendMessageShowDialogDefaultV1 = value;
                  setState(() {});
                },
                title: Text(l10n.settingsShortcutsSendMessageShowDialogDefault),
                description: Text(
                    l10n.settingsShortcutsSendMessageShowDialogDefaultDesc),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
