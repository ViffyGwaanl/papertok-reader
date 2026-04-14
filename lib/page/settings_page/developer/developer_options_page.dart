import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/developer/vibration_test_page.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/widgets/settings/settings_section_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
              SettingsSectionCard(
                title: 'Diagnostics',
                tiles: [
                  SettingsNavRow(
                    icon: Icons.vibration_outlined,
                    title: 'Vibration Test',
                    subtitle: 'Inspect device support and trigger presets',
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (context) => const VibrationTestPage(),
                        ),
                      );
                    },
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
