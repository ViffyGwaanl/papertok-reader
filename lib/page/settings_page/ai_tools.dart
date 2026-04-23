import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/ai_tool_approval_policy.dart';
import 'package:papertok_reader/enums/ai_tool_risk_level.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/page/settings_page/mcp_servers.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/page/settings_page/subpage/share_and_shortcuts_panel_page.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/utils/platform_utils.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:flutter/material.dart';

class AiToolsSettingsPage extends StatefulWidget {
  const AiToolsSettingsPage({super.key});

  @override
  State<AiToolsSettingsPage> createState() => _AiToolsSettingsPageState();
}

class _AiToolsSettingsPageState extends State<AiToolsSettingsPage> {
  String _riskLabel(L10n l10n, AiToolRiskLevel level) {
    return switch (level) {
      AiToolRiskLevel.readOnly => l10n.aiToolRiskReadOnly,
      AiToolRiskLevel.write => l10n.aiToolRiskWrite,
      AiToolRiskLevel.destructive => l10n.aiToolRiskDestructive,
    };
  }

  String _policyLabel(L10n l10n, AiToolApprovalPolicy policy) {
    return switch (policy) {
      AiToolApprovalPolicy.always => l10n.settingsAiToolApprovalPolicyAlways,
      AiToolApprovalPolicy.writesOnly =>
        l10n.settingsAiToolApprovalPolicyWritesOnly,
      AiToolApprovalPolicy.never => l10n.settingsAiToolApprovalPolicyNever,
    };
  }

  Future<void> _pickApprovalPolicy() async {
    final current = Prefs().aiToolApprovalPolicy;
    final l10n = L10n.of(context);

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsAiToolApprovalPolicy,
      builder: (context) {
        void pick(AiToolApprovalPolicy p) {
          Prefs().aiToolApprovalPolicy = p;
          Navigator.pop(context);
          setState(() {});
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PTPickerRow<AiToolApprovalPolicy>(
              value: AiToolApprovalPolicy.always,
              groupValue: current,
              title: l10n.settingsAiToolApprovalPolicyAlways,
              subtitle: l10n.settingsAiToolApprovalPolicyAlwaysDesc,
              onChanged: pick,
            ),
            PTPickerRow<AiToolApprovalPolicy>(
              value: AiToolApprovalPolicy.writesOnly,
              groupValue: current,
              title: l10n.settingsAiToolApprovalPolicyWritesOnly,
              subtitle: l10n.settingsAiToolApprovalPolicyWritesOnlyDesc,
              onChanged: pick,
            ),
            PTPickerRow<AiToolApprovalPolicy>(
              value: AiToolApprovalPolicy.never,
              groupValue: current,
              title: l10n.settingsAiToolApprovalPolicyNever,
              subtitle: l10n.settingsAiToolApprovalPolicyNeverDesc,
              onChanged: pick,
            ),
          ],
        );
      },
    );
  }

  Future<void> _editShortcutsCallbackMaxChars() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    var value = Prefs().shortcutsCallbackMaxCharsV1.toDouble();

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsShortcutsCallbackMaxChars,
      subtitle: l10n.settingsShortcutsCallbackMaxCharsDesc,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value.toInt()} chars',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MorandiPalette.primaryText(context),
                  ),
                ),
                Slider(
                  min: 500,
                  max: 20000,
                  divisions: ((20000 - 500) ~/ 500),
                  value: value.clamp(500, 20000),
                  label: value.toInt().toString(),
                  onChanged: (v) {
                    final snapped = (v / 500).round() * 500;
                    setModalState(() => value = snapped.toDouble());
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Prefs().shortcutsCallbackMaxCharsV1 = value.toInt();
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editShortcutsCallbackTimeoutSec() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    var value = Prefs().shortcutsCallbackTimeoutSecV1.toDouble();

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsShortcutsCallbackTimeout,
      subtitle: l10n.settingsShortcutsCallbackTimeoutDesc,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value.toInt()} sec',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MorandiPalette.primaryText(context),
                  ),
                ),
                Slider(
                  min: 3,
                  max: 300,
                  divisions: (300 - 3),
                  value: value.clamp(3, 300),
                  label: value.toInt().toString(),
                  onChanged: (v) {
                    final snapped = v.round().toDouble();
                    setModalState(() => value = snapped);
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Prefs().shortcutsCallbackTimeoutSecV1 =
                            value.toInt();
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editShortcutsSendMessageTimeoutSec() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    var value = Prefs().shortcutsSendMessageTimeoutSecV1.toDouble();

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsShortcutsSendMessageTimeout,
      subtitle: l10n.settingsShortcutsSendMessageTimeoutDesc,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value.toInt()} sec',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MorandiPalette.primaryText(context),
                  ),
                ),
                Slider(
                  min: 5,
                  max: 180,
                  divisions: (180 - 5),
                  value: value.clamp(5, 180),
                  label: value.toInt().toString(),
                  onChanged: (v) {
                    final snapped = v.round().toDouble();
                    setModalState(() => value = snapped);
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Prefs().shortcutsSendMessageTimeoutSecV1 =
                            value.toInt();
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _shortcutsPresentationLabel(L10n l10n, String code) {
    return switch (code) {
      'new' => l10n.settingsShortcutsSendMessagePresentationNew,
      _ => l10n.settingsShortcutsSendMessagePresentationReuse,
    };
  }

  Future<void> _pickShortcutsSendMessagePresentation() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    final current = Prefs().shortcutsSendMessagePresentationV1;

    void pick(String code) {
      Prefs().shortcutsSendMessagePresentationV1 = code;
      Navigator.pop(context);
      setState(() {});
    }

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsShortcutsSendMessagePresentation,
      subtitle: l10n.settingsShortcutsSendMessagePresentationDesc,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PTPickerRow<String>(
              value: 'reuse',
              groupValue: current,
              title: l10n.settingsShortcutsSendMessagePresentationReuse,
              onChanged: pick,
            ),
            PTPickerRow<String>(
              value: 'new',
              groupValue: current,
              title: l10n.settingsShortcutsSendMessagePresentationNew,
              onChanged: pick,
            ),
          ],
        );
      },
    );
  }

  String _shortcutsWaitModeLabel(L10n l10n, String code) {
    return switch (code) {
      'auto' => l10n.settingsShortcutsWaitModeAuto,
      'preferResult' => l10n.settingsShortcutsWaitModePreferResult,
      'successOnly' => l10n.settingsShortcutsWaitModeSuccessOnly,
      _ => l10n.settingsShortcutsWaitModeAdaptive,
    };
  }

  Future<void> _pickShortcutsWaitMode() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    final current = Prefs().shortcutsCallbackWaitModeV1;
    final learnedCount = Prefs().shortcutsResultKnownNamesV1.length;

    void pick(String code) {
      Prefs().shortcutsCallbackWaitModeV1 = code;
      Navigator.pop(context);
      setState(() {});
    }

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsShortcutsCallbackWaitMode,
      subtitle: '${l10n.settingsShortcutsCallbackWaitModeDesc}\n'
          '${l10n.settingsShortcutsResetLearnedDesc} ($learnedCount)',
      builder: (context) {
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PTPickerRow<String>(
                value: 'adaptive',
                groupValue: current,
                title: l10n.settingsShortcutsWaitModeAdaptive,
                subtitle: l10n.settingsShortcutsWaitModeAdaptiveDesc,
                onChanged: pick,
              ),
              PTPickerRow<String>(
                value: 'auto',
                groupValue: current,
                title: l10n.settingsShortcutsWaitModeAuto,
                subtitle: l10n.settingsShortcutsWaitModeAutoDesc,
                onChanged: pick,
              ),
              PTPickerRow<String>(
                value: 'preferResult',
                groupValue: current,
                title: l10n.settingsShortcutsWaitModePreferResult,
                subtitle: l10n.settingsShortcutsWaitModePreferResultDesc,
                onChanged: pick,
              ),
              PTPickerRow<String>(
                value: 'successOnly',
                groupValue: current,
                title: l10n.settingsShortcutsWaitModeSuccessOnly,
                subtitle: l10n.settingsShortcutsWaitModeSuccessOnlyDesc,
                onChanged: pick,
              ),
              Divider(
                height: 1,
                color: ClaudePalette.divider(context),
              ),
              ListTile(
                title: Text(l10n.settingsShortcutsResetLearned),
                subtitle: Text(l10n.settingsShortcutsResetLearnedDesc),
                onTap: () {
                  Prefs().clearShortcutsResultKnownNamesV1();
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final toolDefs = AiToolRegistry.definitions;
    final enabledToolIds = Prefs().enabledAiToolIds;

    final policy = Prefs().aiToolApprovalPolicy;

    final safetyTiles = <AbstractSettingsTile>[
      SettingsTile.navigation(
        title: Text(l10n.settingsAiToolApprovalPolicy),
        description: Text(l10n.settingsAiToolApprovalPolicyDesc),
        trailing: Text(_policyLabel(l10n, policy)),
        onPressed: (_) => _pickApprovalPolicy(),
      ),
      SettingsTile.switchTile(
        initialValue: Prefs().aiToolForceConfirmDestructive,
        onToggle: (value) {
          Prefs().aiToolForceConfirmDestructive = value;
          setState(() {});
        },
        title: Text(l10n.settingsAiToolForceConfirmDestructive),
        description: Text(l10n.settingsAiToolForceConfirmDestructiveDesc),
      ),
      if (AnxPlatform.isIOS)
        SettingsTile.navigation(
          title: Text(l10n.settingsShareAndShortcutsPanel),
          description: Text(l10n.settingsShareAndShortcutsPanelDesc),
          onPressed: (_) {
            Navigator.push(
              context,
              CupertinoStyleRoute(page: const ShareAndShortcutsPanelPage()),
            );
          },
        ),
      SettingsTile.navigation(
        title: Text(l10n.settingsMcpServers),
        description: Text(l10n.settingsMcpServersDesc),
        onPressed: (_) {
          Navigator.push(
            context,
            CupertinoStyleRoute(
              page: SettingsSubpageScaffold(
                title: l10n.settingsMcpServers,
                child: const McpServersSettingsPage(),
              ),
            ),
          );
        },
      ),
      SettingsTile.switchTile(
        initialValue: Prefs().mcpAutoRefreshToolsV1,
        onToggle: (value) {
          Prefs().mcpAutoRefreshToolsV1 = value;
          setState(() {});
        },
        title: Text(l10n.settingsMcpAutoRefreshTools),
        description: Text(l10n.settingsMcpAutoRefreshToolsDesc),
      ),
    ];

    final toolsTile = CustomSettingsTile(
      child: Column(
        children: [
          for (final tool in toolDefs)
            SettingsTile.switchTile(
              initialValue: enabledToolIds.contains(tool.id),
              onToggle: (value) {
                final next = Set<String>.from(enabledToolIds);
                if (value) {
                  next.add(tool.id);
                } else {
                  next.remove(tool.id);
                }
                Prefs().enabledAiToolIds = next.toList();
                setState(() {});
              },
              title: Text(tool.displayName(l10n)),
              description: Text(
                '${_riskLabel(l10n, tool.riskLevel)} • ${tool.description(l10n)}',
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Prefs().resetEnabledAiTools();
                setState(() {});
              },
              child: Text(l10n.commonReset),
            ),
          ),
        ],
      ),
    );

    return settingsSections(sections: [
      SettingsSection(
        title: Text(l10n.settingsAiToolSafety),
        tiles: safetyTiles,
      ),
      SettingsSection(
        title: Text(l10n.settingsAiTools),
        tiles: [
          toolsTile,
        ],
      ),
    ]);
  }
}
