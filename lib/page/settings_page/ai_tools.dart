import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_tool_approval_policy.dart';
import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/page/settings_page/mcp_servers.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/utils/platform_utils.dart';
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

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text(l10n.settingsAiToolApprovalPolicyAlways),
                subtitle: Text(l10n.settingsAiToolApprovalPolicyAlwaysDesc),
                trailing: current == AiToolApprovalPolicy.always
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Prefs().aiToolApprovalPolicy = AiToolApprovalPolicy.always;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.settingsAiToolApprovalPolicyWritesOnly),
                subtitle: Text(l10n.settingsAiToolApprovalPolicyWritesOnlyDesc),
                trailing: current == AiToolApprovalPolicy.writesOnly
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Prefs().aiToolApprovalPolicy =
                      AiToolApprovalPolicy.writesOnly;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(l10n.settingsAiToolApprovalPolicyNever),
                subtitle: Text(l10n.settingsAiToolApprovalPolicyNeverDesc),
                trailing: current == AiToolApprovalPolicy.never
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Prefs().aiToolApprovalPolicy = AiToolApprovalPolicy.never;
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

  Future<void> _editShortcutsCallbackMaxChars() async {
    if (!AnxPlatform.isIOS) return;

    final l10n = L10n.of(context);
    var value = Prefs().shortcutsCallbackMaxCharsV1.toDouble();

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsShortcutsCallbackMaxChars,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.settingsShortcutsCallbackMaxCharsDesc,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${value.toInt()} chars',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                ),
              ),
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

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsShortcutsCallbackTimeout,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.settingsShortcutsCallbackTimeoutDesc,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${value.toInt()} sec',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                ),
              ),
            );
          },
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

    Widget item({
      required String code,
      required String title,
      required String desc,
    }) {
      return ListTile(
        title: Text(title),
        subtitle: Text(desc),
        trailing: current == code ? const Icon(Icons.check) : null,
        onTap: () {
          Prefs().shortcutsCallbackWaitModeV1 = code;
          Navigator.pop(context);
          setState(() {});
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text(l10n.settingsShortcutsCallbackWaitMode),
                subtitle: Text(
                  '${l10n.settingsShortcutsCallbackWaitModeDesc}\n'
                  '${l10n.settingsShortcutsResetLearnedDesc} ($learnedCount)',
                ),
              ),
              const Divider(height: 1),
              item(
                code: 'adaptive',
                title: l10n.settingsShortcutsWaitModeAdaptive,
                desc: l10n.settingsShortcutsWaitModeAdaptiveDesc,
              ),
              const Divider(height: 1),
              item(
                code: 'auto',
                title: l10n.settingsShortcutsWaitModeAuto,
                desc: l10n.settingsShortcutsWaitModeAutoDesc,
              ),
              const Divider(height: 1),
              item(
                code: 'preferResult',
                title: l10n.settingsShortcutsWaitModePreferResult,
                desc: l10n.settingsShortcutsWaitModePreferResultDesc,
              ),
              const Divider(height: 1),
              item(
                code: 'successOnly',
                title: l10n.settingsShortcutsWaitModeSuccessOnly,
                desc: l10n.settingsShortcutsWaitModeSuccessOnlyDesc,
              ),
              const Divider(height: 1),
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
      if (AnxPlatform.isIOS) ...[
        SettingsTile.navigation(
          title: Text(l10n.settingsShortcutsCallbackMaxChars),
          description: Text(l10n.settingsShortcutsCallbackMaxCharsDesc),
          trailing: Text('${Prefs().shortcutsCallbackMaxCharsV1}'),
          onPressed: (_) => _editShortcutsCallbackMaxChars(),
        ),
        SettingsTile.navigation(
          title: Text(l10n.settingsShortcutsCallbackTimeout),
          description: Text(l10n.settingsShortcutsCallbackTimeoutDesc),
          trailing: Text('${Prefs().shortcutsCallbackTimeoutSecV1}s'),
          onPressed: (_) => _editShortcutsCallbackTimeoutSec(),
        ),
        SettingsTile.navigation(
          title: Text(l10n.settingsShortcutsCallbackWaitMode),
          description: Text(l10n.settingsShortcutsCallbackWaitModeDesc),
          trailing: Text(
            _shortcutsWaitModeLabel(
              l10n,
              Prefs().shortcutsCallbackWaitModeV1,
            ),
          ),
          onPressed: (_) => _pickShortcutsWaitMode(),
        ),
      ],
      SettingsTile.navigation(
        title: Text(l10n.settingsMcpServers),
        description: Text(l10n.settingsMcpServersDesc),
        onPressed: (_) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SettingsSubpageScaffold(
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
