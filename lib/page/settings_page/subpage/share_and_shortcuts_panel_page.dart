import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/page/settings_page/subpage/share_inbox_diagnostics_page.dart';
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

  String _sessionModeLabel(L10n l10n, String code) {
    return switch (code) {
      'new' => l10n.settingsShareConversationModeNew,
      _ => l10n.settingsShareConversationModeReuse,
    };
  }

  String _shortcutsPresetModeLabel(L10n l10n, String code) {
    return switch (code) {
      'when_empty' => l10n.settingsShortcutsPromptPresetModeWhenEmpty,
      'prepend' => l10n.settingsShortcutsPromptPresetModePrepend,
      _ => l10n.settingsShortcutsPromptPresetModeOff,
    };
  }

  String _shortcutsPresetLabel(L10n l10n) {
    final id = Prefs().shortcutsPromptPresetIdV1.trim();
    if (id.isEmpty) return l10n.commonNone;
    for (final preset in Prefs().sharePromptPresetsStateV2.enabledPresets) {
      if (preset.id == id) {
        return preset.title.trim().isEmpty ? id : preset.title;
      }
    }
    return l10n.commonNone;
  }

  Future<void> _pickSessionMode() async {
    final l10n = L10n.of(context);
    final current = Prefs().shortcutsSendMessagePresentationV1;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsShareConversationModeTitle),
          children: [
            RadioListTile<String>(
              value: 'reuse',
              groupValue: current,
              title: Text(l10n.settingsShareConversationModeReuse),
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
            RadioListTile<String>(
              value: 'new',
              groupValue: current,
              title: Text(l10n.settingsShareConversationModeNew),
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().shortcutsSendMessagePresentationV1 = picked;
      setState(() {});
    }
  }

  String _countLabel(int count) => '$count';

  Future<void> _pickImageAttachmentMax() async {
    final l10n = L10n.of(context);
    final current = Prefs().aiChatImageAttachmentMaxCountV1;
    const options = <int>[1, 2, 4, 6, 8];

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsAiChatImageAttachmentMaxCountTitle),
          children: [
            for (final v in options)
              RadioListTile<int>(
                value: v,
                groupValue: current,
                title: Text(l10n.settingsAiChatAttachmentCount(v)),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().aiChatImageAttachmentMaxCountV1 = picked;
      setState(() {});
    }
  }

  Future<void> _pickTextAttachmentMax() async {
    final l10n = L10n.of(context);
    final current = Prefs().aiChatTextAttachmentMaxCountV1;
    const options = <int>[1, 3, 5, 8, 10];

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsAiChatTextAttachmentMaxCountTitle),
          children: [
            for (final v in options)
              RadioListTile<int>(
                value: v,
                groupValue: current,
                title: Text(l10n.settingsAiChatAttachmentCount(v)),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().aiChatTextAttachmentMaxCountV1 = picked;
      setState(() {});
    }
  }

  Future<void> _pickShortcutsPresetMode() async {
    final l10n = L10n.of(context);
    final current = Prefs().shortcutsPromptPresetModeV1;
    const options = <String>['off', 'when_empty', 'prepend'];

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsShortcutsPromptPresetModeTitle),
          children: [
            for (final v in options)
              RadioListTile<String>(
                value: v,
                groupValue: current,
                title: Text(_shortcutsPresetModeLabel(l10n, v)),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().shortcutsPromptPresetModeV1 = picked;
      setState(() {});
    }
  }

  Future<void> _pickShortcutsPreset() async {
    final l10n = L10n.of(context);
    final current = Prefs().shortcutsPromptPresetIdV1.trim();
    final presets = Prefs().sharePromptPresetsStateV2.enabledPresets;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsShortcutsPromptPresetTitle),
          children: [
            RadioListTile<String>(
              value: '',
              groupValue: current,
              title: Text(l10n.commonNone),
              onChanged: (val) => Navigator.of(ctx).pop(val),
            ),
            for (final preset in presets)
              RadioListTile<String>(
                value: preset.id,
                groupValue: current,
                title: Text(
                  preset.title.trim().isEmpty ? preset.id : preset.title,
                ),
                subtitle: preset.prompt.trim().isEmpty
                    ? null
                    : Text(
                        preset.prompt.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onChanged: (val) => Navigator.of(ctx).pop(val),
              ),
          ],
        );
      },
    );

    if (picked != null) {
      Prefs().shortcutsPromptPresetIdV1 = picked;
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
      child: ListView(
        padding: EdgeInsets.zero,
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
                title: Text(l10n.settingsShareConversationModeTitle),
                description: Text(l10n.settingsShareConversationModeDesc),
                trailing: Text(_sessionModeLabel(
                  l10n,
                  Prefs().shortcutsSendMessagePresentationV1,
                )),
                onPressed: (_) => _pickSessionMode(),
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsAiChatImageAttachmentMaxCountTitle),
                description:
                    Text(l10n.settingsAiChatImageAttachmentMaxCountDesc),
                trailing:
                    Text(_countLabel(Prefs().aiChatImageAttachmentMaxCountV1)),
                onPressed: (_) => _pickImageAttachmentMax(),
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsAiChatTextAttachmentMaxCountTitle),
                description:
                    Text(l10n.settingsAiChatTextAttachmentMaxCountDesc),
                trailing:
                    Text(_countLabel(Prefs().aiChatTextAttachmentMaxCountV1)),
                onPressed: (_) => _pickTextAttachmentMax(),
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
              SettingsTile.navigation(
                title: Text(l10n.settingsShareInboxDiagnosticsTitle),
                description: Text(l10n.settingsShareInboxDiagnosticsDesc),
                onPressed: (_) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ShareInboxDiagnosticsPage(),
                    ),
                  );
                },
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
              SettingsTile.navigation(
                title: Text(l10n.settingsShortcutsPromptPresetModeTitle),
                description: Text(l10n.settingsShortcutsPromptPresetModeDesc),
                trailing: Text(
                  _shortcutsPresetModeLabel(
                    l10n,
                    Prefs().shortcutsPromptPresetModeV1,
                  ),
                ),
                onPressed: (_) => _pickShortcutsPresetMode(),
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsShortcutsPromptPresetTitle),
                description: Text(l10n.settingsShortcutsPromptPresetDesc),
                trailing: Text(_shortcutsPresetLabel(l10n)),
                onPressed: (_) => _pickShortcutsPreset(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
