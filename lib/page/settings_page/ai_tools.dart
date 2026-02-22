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
