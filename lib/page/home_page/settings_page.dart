import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:anx_reader/page/settings_page/ai_image_analysis.dart';
import 'package:anx_reader/page/settings_page/ai_tools.dart';
import 'package:anx_reader/page/settings_page/advanced.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/page/settings_page/home_navigation.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/reading.dart';
import 'package:anx_reader/page/settings_page/storege.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: EdgeInsets.only(
                  // HomePage already reserves enough space for the floating tab
                  // bar on phones. Avoid double-padding here.
                  bottom: MediaQuery.of(context).size.width <= 600
                      ? 12
                      : (MediaQuery.of(context).padding.bottom + 12),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const Divider(),
                    // Main settings entries (flattened; previously lived under
                    // “More Settings”).
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title:
                                Text(L10n.of(context).settingsHomeNavigation),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) =>
                                      const HomeNavigationSettingsPage(),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.color_lens_outlined),
                            title: Text(L10n.of(context).settingsAppearance),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsAppearance,
                                    child: const AppearanceSetting(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.book_rounded),
                            title: Text(L10n.of(context).settingsReading),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsReading,
                                    child: const ReadingSettings(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.sync_outlined),
                            title: Text(L10n.of(context).settingsSync),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsSync,
                                    child: const SyncSetting(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.translate_outlined),
                            title: Text(L10n.of(context).settingsTranslate),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsTranslate,
                                    child: const TranslateSetting(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.headphones),
                            title: Text(L10n.of(context).settingsNarrate),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsNarrate,
                                    child: const NarrateSettings(),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (EnvVar.enableAIFeature) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.auto_awesome),
                              title: Text(L10n.of(context).settingsAi),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (context) =>
                                        SettingsSubpageScaffold(
                                      title: L10n.of(context).settingsAi,
                                      child: const AISettings(),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.hub_outlined),
                              title: Text(
                                L10n.of(context).settingsAiProviderCenterTitle,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (context) =>
                                        const AiProviderCenterPage(),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.handyman_outlined),
                              title: Text(L10n.of(context).settingsAiTools),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (context) =>
                                        SettingsSubpageScaffold(
                                      title: L10n.of(context).settingsAiTools,
                                      child: const AiToolsSettingsPage(),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.image_outlined),
                              title: Text(
                                L10n.of(context).settingsAiImageAnalysisTitle,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (context) =>
                                        SettingsSubpageScaffold(
                                      title: L10n.of(context)
                                          .settingsAiImageAnalysisTitle,
                                      child:
                                          const AiImageAnalysisSettingsPage(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.storage_outlined),
                            title: Text(L10n.of(context).storage),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).storage,
                                    child: const StorageSettings(),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.shield_outlined),
                            title: Text(L10n.of(context).settingsAdvanced),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => SettingsSubpageScaffold(
                                    title: L10n.of(context).settingsAdvanced,
                                    child: const AdvancedSetting(),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Developer Options tile is rendered below (with onTap).
                        ],
                      ),
                    ),
                    if (Prefs().developerOptionsEnabled)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ListTile(
                          leading: const Icon(Icons.developer_mode),
                          title: const Text('Developer Options'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) =>
                                    const DeveloperOptionsPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(L10n.of(context).appAbout),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          openAboutDialog();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
