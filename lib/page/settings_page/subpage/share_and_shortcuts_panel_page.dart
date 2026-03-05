import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
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
  Future<void> _pickSharePanelMode() async {
    final l10n = L10n.of(context);
    final current = Prefs().sharePanelModeV1;

    String label(String v) {
      switch (v) {
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

  Future<void> _editSharePanelPrompt() async {
    final l10n = L10n.of(context);
    final controller = TextEditingController(text: Prefs().sharePanelPromptV1);

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.settingsSharePanelPromptTitle),
          content: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 3,
            decoration: InputDecoration(
              hintText: l10n.settingsSharePanelPromptHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().sharePanelPromptV1 = picked;
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
                title: Text(l10n.settingsSharePanelPromptTitle),
                description: Text(l10n.settingsSharePanelPromptDesc),
                onPressed: (_) => _editSharePanelPrompt(),
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
