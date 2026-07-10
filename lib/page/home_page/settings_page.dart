import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/ai.dart';
import 'package:papertok_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/memory.dart';
import 'package:papertok_reader/page/settings_page/advanced.dart';
import 'package:papertok_reader/page/settings_page/appearance.dart';
import 'package:papertok_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:papertok_reader/page/settings_page/home_navigation.dart';
import 'package:papertok_reader/page/settings_page/narrate.dart';
import 'package:papertok_reader/page/settings_page/reading.dart';
import 'package:papertok_reader/page/settings_page/storege.dart';
import 'package:papertok_reader/page/settings_page/sync.dart';
import 'package:papertok_reader/page/settings_page/translate.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/utils/env_var.dart';
import 'package:papertok_reader/widgets/settings/about.dart';
import 'package:papertok_reader/widgets/settings/settings_icon_label.dart';
import 'package:papertok_reader/widgets/settings/settings_section_card.dart';
import 'package:papertok_reader/page/home_page/home_bottom_inset_scope.dart';
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

  void _pushSubpage(BuildContext context, String title, Widget child) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => SettingsSubpageScaffold(
          title: title,
          child: child,
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final l10n = L10n.of(context);
        final bottomInset = MediaQuery.of(context).size.width <= 600
            ? (HomeBottomInsetScope.of(context) + 12)
            : (MediaQuery.of(context).padding.bottom + 12);

        // E4 batch 3: geek-facing entries (tool management, library index,
        // MCP, custom skills, quick prompts, seminar config, concept graph,
        // knowledge export) live under Developer Options; image analysis
        // moved inside the AI settings subpage. First level keeps three.
        final aiTiles = <Widget>[
          SettingsNavRow(
            icon: Icons.hub_outlined,
            tint: SettingsIconTints.network,
            title: l10n.settingsAiProviderCenterTitle,
            onTap: () => _push(context, const AiProviderCenterPage()),
          ),
          SettingsNavRow(
            icon: Icons.auto_awesome,
            tint: SettingsIconTints.sparkles,
            title: l10n.settingsAi,
            onTap: () =>
                _pushSubpage(context, l10n.settingsAi, const AISettings()),
          ),
          SettingsNavRow(
            icon: Icons.fact_check_outlined,
            tint: SettingsIconTints.memory,
            title: l10n.reviewInboxTitle,
            onTap: () => _push(context, const ReviewInboxPage()),
          ),
        ];

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Reading
                      SettingsSectionCard(
                        title: l10n.settingsReading,
                        tiles: [
                          SettingsNavRow(
                            icon: Icons.book_rounded,
                            tint: SettingsIconTints.reading,
                            title: l10n.settingsReading,
                            onTap: () => _pushSubpage(context,
                                l10n.settingsReading, const ReadingSettings()),
                          ),
                          if (EnvVar.enableAIFeature)
                            SettingsNavRow(
                              icon: Icons.translate_outlined,
                              tint: SettingsIconTints.translate,
                              title: l10n.settingsTranslate,
                              onTap: () => _pushSubpage(
                                  context,
                                  l10n.settingsTranslate,
                                  const TranslateSetting()),
                            ),
                          SettingsNavRow(
                            icon: Icons.headphones,
                            tint: SettingsIconTints.tts,
                            title: l10n.settingsNarrate,
                            onTap: () => _pushSubpage(context,
                                l10n.settingsNarrate, const NarrateSettings()),
                          ),
                          if (EnvVar.enableAIFeature)
                            SettingsNavRow(
                              icon: Icons.psychology_outlined,
                              tint: SettingsIconTints.memory,
                              title: l10n.settingsMemory,
                              onTap: () =>
                                  _push(context, const MemorySettingsPage()),
                            ),
                        ],
                      ),

                      // AI & Assistant
                      if (EnvVar.enableAIFeature)
                        SettingsSectionCard(
                          title: l10n.settingsAi,
                          tiles: aiTiles,
                        ),

                      // Sync & Data
                      SettingsSectionCard(
                        title: l10n.settingsSync,
                        tiles: [
                          SettingsNavRow(
                            icon: Icons.sync_outlined,
                            tint: SettingsIconTints.sync,
                            title: l10n.settingsSync,
                            onTap: () => _pushSubpage(context,
                                l10n.settingsSync, const SyncSetting()),
                          ),
                          SettingsNavRow(
                            icon: Icons.storage_outlined,
                            tint: SettingsIconTints.storage,
                            title: l10n.storage,
                            onTap: () => _pushSubpage(
                                context, l10n.storage, const StorageSettings()),
                          ),
                        ],
                      ),

                      // Customization
                      SettingsSectionCard(
                        title: l10n.settingsAppearance,
                        tiles: [
                          SettingsNavRow(
                            icon: Icons.color_lens_outlined,
                            tint: SettingsIconTints.appearance,
                            title: l10n.settingsAppearance,
                            onTap: () => _pushSubpage(
                                context,
                                l10n.settingsAppearance,
                                const AppearanceSetting()),
                          ),
                          SettingsNavRow(
                            icon: Icons.home_outlined,
                            tint: SettingsIconTints.homeNav,
                            title: l10n.settingsHomeNavigation,
                            onTap: () => _push(
                                context, const HomeNavigationSettingsPage()),
                          ),
                        ],
                      ),

                      // Advanced
                      SettingsSectionCard(
                        title: l10n.settingsAdvanced,
                        tiles: [
                          SettingsNavRow(
                            icon: Icons.shield_outlined,
                            tint: SettingsIconTints.advanced,
                            title: l10n.settingsAdvanced,
                            onTap: () => _pushSubpage(context,
                                l10n.settingsAdvanced, const AdvancedSetting()),
                          ),
                          if (Prefs().developerOptionsEnabled)
                            SettingsNavRow(
                              icon: Icons.developer_mode,
                              tint: SettingsIconTints.advanced,
                              title: 'Developer Options',
                              onTap: () =>
                                  _push(context, const DeveloperOptionsPage()),
                            ),
                        ],
                      ),

                      // About
                      SettingsSectionCard(
                        title: l10n.appAbout,
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        tiles: [
                          SettingsNavRow(
                            icon: Icons.info_outline,
                            tint: SettingsIconTints.about,
                            title: l10n.appAbout,
                            onTap: () => openAboutDialog(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
