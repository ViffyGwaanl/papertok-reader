import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/ai_prompts.dart';
import 'package:papertok_reader/enums/ai_dock_side.dart';
import 'package:papertok_reader/enums/ai_pad_panel_mode.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/ai_cache_count.dart';
import 'package:papertok_reader/providers/user_prompts.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/page/settings_page/ai_title_generation.dart';
import 'package:papertok_reader/page/settings_page/ai_tools.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/settings_page/knowledge_asset_export.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/widgets/common/anx_button.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/widgets/delete_confirm.dart';
import 'package:papertok_reader/page/settings_page/ai_quick_prompts_editor.dart';
import 'package:papertok_reader/page/settings_page/subpage/log_page.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:papertok_reader/utils/toast/common.dart';

class AISettings extends ConsumerStatefulWidget {
  const AISettings({super.key});

  @override
  ConsumerState<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends ConsumerState<AISettings> {
  bool showSettings = false;
  int currentIndex = 0;
  late List<Map<String, dynamic>> initialServicesConfig;

  // User prompts state
  String? _expandedUserPromptId;
  final Map<String, TextEditingController> _userPromptNameControllers = {};
  final Map<String, TextEditingController> _userPromptContentControllers = {};

  late final List<AiServiceOption> serviceOptions;
  late List<Map<String, dynamic>> services;

  @override
  void initState() {
    serviceOptions = buildDefaultAiServices();
    services = serviceOptions.map(
      (option) {
        return {
          'identifier': option.identifier,
          'title': option.title,
          'logo': option.logo,
          'config': {
            'url': option.defaultUrl,
            'api_key': option.defaultApiKey,
            'model': option.defaultModel,
          },
        };
      },
    ).toList();
    initialServicesConfig = services
        .map(
          (service) => {
            ...service,
            'config': Map<String, String>.from(
              service['config'] as Map<String, String>,
            ),
          },
        )
        .toList();
    for (final service in services) {
      final stored = Prefs().getAiConfig(service['identifier'] as String);
      final config = service['config'] as Map<String, String>;
      for (final entry in stored.entries) {
        config[entry.key] = entry.value;
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    // Clean up user prompt controllers
    for (var controller in _userPromptNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _userPromptContentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    List<Map<String, dynamic>> prompts = [
      {
        "identifier": AiPrompts.test,
        "title": l10n.settingsAiPromptTest,
        "variables": ["language_locale"],
      },
      {
        "identifier": AiPrompts.summaryTheChapter,
        "title": l10n.settingsAiPromptSummaryTheChapter,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryTheBook,
        "title": l10n.settingsAiPromptSummaryTheBook,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryThePreviousContent,
        "title": l10n.settingsAiPromptSummaryThePreviousContent,
        "variables": ["previous_content"],
      },
      {
        "identifier": AiPrompts.translate,
        "title": l10n.settingsAiPromptTranslateAndDictionary,
        "variables": ["text", "to_locale", "from_locale", "contextText"],
      },
      {
        "identifier": AiPrompts.translateFulltext,
        "title": l10n.settingsAiPromptTranslateFulltext,
        "variables": ["text", "to_locale", "from_locale", "contextText"],
      },
      {
        "identifier": AiPrompts.mindmap,
        "title": l10n.settingsAiPromptMindmap,
        "variables": [],
      }
    ];

    final servicesTile = CustomSettingsTile(
      child: SettingsTile.navigation(
        title: Text(l10n.settingsAiProviderCenterTitle),
        description: Text(l10n.settingsAiProviderCenterDesc),
        onPressed: (context) {
          Navigator.of(context).push(
            CupertinoStyleRoute(page: const AiProviderCenterPage()),
          );
        },
      ),
    );

    var promptTile = CustomSettingsTile(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          return SettingsTile.navigation(
            title: Text(prompts[index]["title"]),
            onPressed: (context) {
              SmartDialog.show(builder: (context) {
                final controller = TextEditingController(
                  text: Prefs().getAiPrompt(
                    AiPrompts.values[index],
                  ),
                );

                return PTDialog(
                  title: L10n.of(context).commonEdit,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        maxLines: 10,
                        controller: controller,
                      ),
                      Wrap(
                        children: [
                          for (var variable in prompts[index]["variables"])
                            TextButton(
                              onPressed: () {
                                // insert the variables at the cursor
                                if (controller.selection.start == -1 ||
                                    controller.selection.end == -1) {
                                  return;
                                }

                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: controller.selection.start,
                                  ),
                                );

                                controller.text = controller.text.replaceRange(
                                  controller.selection.start,
                                  controller.selection.end,
                                  '{{$variable}}',
                                );
                              },
                              child: Text(
                                '{{$variable}}',
                              ),
                            ),
                        ],
                      )
                    ],
                  ),
                  actions: [
                    PTDialogAction(
                      label: L10n.of(context).commonReset,
                      onPressed: () {
                        Prefs().deleteAiPrompt(AiPrompts.values[index]);
                        controller.text = Prefs().getAiPrompt(
                          AiPrompts.values[index],
                        );
                      },
                    ),
                    PTDialogAction(
                      label: L10n.of(context).commonSave,
                      isDefault: true,
                      onPressed: () {
                        Prefs().saveAiPrompt(
                          AiPrompts.values[index],
                          controller.text,
                        );
                      },
                    ),
                  ],
                );
              });
            },
          );
        },
      ),
    );

    // AI tools are managed in Settings → AI Tools.

    return settingsSections(sections: [
      SettingsSection(
        title: Text(L10n.of(context).settingsAiServices),
        tiles: [
          servicesTile,
          SettingsTile.navigation(
            title: Text(l10n.settingsAiConversationTitles),
            description: Text(l10n.settingsAiConversationTitlesDesc),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(
                  page: SettingsSubpageScaffold(
                    title: l10n.settingsAiConversationTitles,
                    child: const AiTitleGenerationSettingsPage(),
                  ),
                ),
              );
            },
          ),
          // SettingsTile.navigation(
          //   leading: const Icon(Icons.chat),
          //   title: Text(L10n.of(context).aiChat),
          //   onPressed: (context) {
          //     Navigator.push(
          //       context,
          //       CupertinoPageRoute(
          //         builder: (context) => const AiChatPage(),
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiPrompt),
        tiles: [
          promptTile,
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiUserPrompts),
        tiles: [
          userPromptsTile(),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiTools),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.settingsAiTools),
            trailing: const Icon(Icons.chevron_right),
            onPressed: (context) {
              Navigator.push(
                context,
                CupertinoStyleRoute(
                  page: SettingsSubpageScaffold(
                    title: l10n.settingsAiTools,
                    child: const AiToolsSettingsPage(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      // iPad-specific AI panel settings (only show on larger screens)
      if (MediaQuery.of(context).size.width >= 600)
        SettingsSection(
          title: Text(l10n.settingsAiPadPanelMode),
          tiles: [
            SettingsTile.switchTile(
              title: Text(l10n.settingsAiPadPanelModeBottomSheet),
              description: Text(l10n.settingsAiPadPanelModeDock),
              initialValue:
                  Prefs().aiPadPanelMode == AiPadPanelModeEnum.bottomSheet,
              onToggle: (value) {
                setState(() {
                  Prefs().aiPadPanelMode = value
                      ? AiPadPanelModeEnum.bottomSheet
                      : AiPadPanelModeEnum.dock;
                });
              },
            ),
            // Dock side only relevant when in dock mode
            if (Prefs().aiPadPanelMode == AiPadPanelModeEnum.dock)
              SettingsTile.navigation(
                title: Text(l10n.settingsAiDockSide),
                value: Text(Prefs().aiDockSide == AiDockSideEnum.left
                    ? l10n.settingsAiDockSideLeft
                    : l10n.settingsAiDockSideRight),
                onPressed: (context) {
                  setState(() {
                    Prefs().aiDockSide =
                        Prefs().aiDockSide == AiDockSideEnum.left
                            ? AiDockSideEnum.right
                            : AiDockSideEnum.left;
                  });
                },
              ),
          ],
        ),
      SettingsSection(
        title: Text(l10n.settingsAiQuickPrompts),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.settingsAiQuickPrompts),
            description: Text(l10n.settingsAiQuickPromptsHint),
            onPressed: (context) {
              Navigator.push(
                context,
                CupertinoStyleRoute(page: const AiQuickPromptsEditor()),
              );
            },
          ),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiFeatures),
        tiles: [
          SettingsTile.navigation(
            leading: const Icon(Icons.groups_2_outlined),
            title: Text(l10n.aiSkillSeminarModeName),
            description: Text(l10n.aiSkillSeminarModeDesc),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const AiSeminarRuntimePage()),
              );
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.auto_awesome),
            title: Text(l10n.settingsAiKairos),
            description: Text(
              Prefs().kairosLevel == 0
                  ? l10n.settingsAiKairosOff
                  : [
                      '',
                      l10n.settingsAiKairosLevelLight,
                      l10n.settingsAiKairosLevelMedium,
                      l10n.settingsAiKairosLevelEager
                    ][Prefs().kairosLevel],
            ),
            onPressed: (context) {
              _showKairosLevelPicker(context);
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(l10n.reviewInboxTitle),
            description: Text(l10n.reviewInboxDescription),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const ReviewInboxPage()),
              );
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.conceptGraphTitle),
            description: Text(l10n.conceptGraphDescription),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const ConceptGraphExplorerPage()),
              );
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.school_outlined),
            title: Text(l10n.spacedReviewTitle),
            description: Text(l10n.spacedReviewDescription),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const SpacedReviewPage()),
              );
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.ios_share_outlined),
            title: Text(l10n.knowledgeExportTitle),
            description: Text(l10n.knowledgeExportDescription),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const KnowledgeAssetExportPage()),
              );
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.auto_fix_high),
            title: Text(l10n.settingsAiActiveSkill),
            description: Text(
              _localizedSkillName(context, Prefs().activeAiSkillId) ??
                  l10n.settingsAiSkillNone,
            ),
            onPressed: (context) {
              _showSkillPicker(context);
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.search),
            title: Text(l10n.settingsAiWebSearch),
            description: Text(
              _hasWebSearchApiKey()
                  ? l10n.settingsAiWebSearchConfigured
                  : l10n.settingsAiWebSearchDefault,
            ),
            onPressed: (context) {
              _showWebSearchApiKeyDialog(context);
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.memory),
            title: Text(l10n.settingsAiLocalEmbedding),
            description: Text(
              (Prefs().localEmbeddingEndpoint ?? '').isNotEmpty
                  ? '${Prefs().localEmbeddingEndpoint} (${Prefs().localEmbeddingModel})'
                  : l10n.settingsAiLocalEmbeddingNotConfigured,
            ),
            onPressed: (context) {
              _showLocalEmbeddingDialog(context);
            },
          ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiCache),
        tiles: [
          CustomSettingsTile(
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(L10n.of(context).settingsAiCacheSize),
                  Text(
                    L10n.of(context).settingsAiCacheCurrentSize(ref
                        .watch(aiCacheCountProvider)
                        .when(
                            data: (value) => value,
                            loading: () => 0,
                            error: (error, stack) => 0)),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Text(Prefs().maxAiCacheCount.toString()),
                  Expanded(
                    child: Slider(
                      value: Prefs().maxAiCacheCount.toDouble(),
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: Prefs().maxAiCacheCount.toString(),
                      onChanged: (value) {
                        Prefs().maxAiCacheCount = value.toInt();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAiCacheClear),
              onPressed: (context) {
                SmartDialog.show(
                  builder: (context) => PTDialog(
                    title: L10n.of(context).commonConfirm,
                    actions: [
                      PTDialogAction(
                        label: L10n.of(context).commonCancel,
                        onPressed: () {
                          SmartDialog.dismiss();
                        },
                      ),
                      PTDialogAction(
                        label: L10n.of(context).commonConfirm,
                        destructive: true,
                        onPressed: () {
                          ref.read(aiCacheCountProvider.notifier).clearCache();
                          SmartDialog.dismiss();
                        },
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiDebugTitle),
        tiles: [
          SettingsTile.switchTile(
            leading: const Icon(Icons.developer_mode),
            title: Text(l10n.settingsAiDebugEnable),
            description: Text(l10n.settingsAiDebugEnableDesc),
            initialValue: Prefs().aiDebugLogsEnabled,
            onToggle: (value) {
              setState(() {
                Prefs().aiDebugLogsEnabled = value;
              });
            },
          ),
          SettingsTile.navigation(
            leading: const Icon(Icons.bug_report),
            title: Text(L10n.of(context).settingsAdvancedLog),
            onPressed: (context) {
              Navigator.of(context).push(
                CupertinoStyleRoute(page: const LogPage()),
              );
            },
          ),
        ],
      ),
    ]);
  }

  void _showKairosLevelPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l = L10n.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              ListTile(
                title: Text(l.settingsAiKairosPickerTitle),
                subtitle: Text(l.settingsAiKairosPickerDesc),
              ),
              const Divider(),
              _kairosOption(context, 0, l.settingsAiKairosPickerOffTitle,
                  l.settingsAiKairosPickerOffDesc),
              _kairosOption(context, 1, l.settingsAiKairosPickerLightTitle,
                  l.settingsAiKairosPickerLightDesc),
              _kairosOption(context, 2, l.settingsAiKairosPickerMediumTitle,
                  l.settingsAiKairosPickerMediumDesc),
              _kairosOption(context, 3, l.settingsAiKairosPickerEagerTitle,
                  l.settingsAiKairosPickerEagerDesc),
            ],
          ),
        );
      },
    );
  }

  Widget _kairosOption(
      BuildContext context, int level, String title, String subtitle) {
    final isSelected = Prefs().kairosLevel == level;
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        setState(() {
          Prefs().kairosLevel = level;
        });
        Navigator.pop(context);
      },
    );
  }

  void _showSkillPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l = L10n.of(context);
        final skills = AiSkillRegistry.allSkills();
        final activeId = Prefs().activeAiSkillId;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              ListTile(
                title: Text(l.settingsAiSkillPickerTitle),
                subtitle: Text(l.settingsAiSkillPickerDesc),
              ),
              const Divider(),
              ListTile(
                title: Text(l.settingsAiSkillPickerNoneTitle),
                subtitle: Text(l.settingsAiSkillPickerNoneDesc),
                trailing: activeId == null
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() {
                    Prefs().activeAiSkillId = null;
                  });
                  Navigator.pop(context);
                },
              ),
              ...skills.map((skill) {
                final isSelected = skill.id == activeId;
                return ListTile(
                  leading: const Icon(
                    Icons.auto_fix_high,
                    size: 20,
                  ),
                  title: Text(
                      _localizedSkillName(context, skill.id) ?? skill.name),
                  subtitle: Text(
                    _localizedSkillDesc(context, skill.id) ?? skill.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      Prefs().activeAiSkillId = skill.id;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String? _localizedSkillName(BuildContext context, String? id) {
    if (id == null) return null;
    final l = L10n.of(context);
    switch (id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerName;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorName;
      case 'debate_partner':
        return l.aiSkillDebatePartnerName;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorName;
      case 'reading_companion':
        return l.aiSkillReadingCompanionName;
      case 'seminar_mode':
        return l.aiSkillSeminarModeName;
      default:
        return null;
    }
  }

  String? _localizedSkillDesc(BuildContext context, String? id) {
    if (id == null) return null;
    final l = L10n.of(context);
    switch (id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerDesc;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorDesc;
      case 'debate_partner':
        return l.aiSkillDebatePartnerDesc;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorDesc;
      case 'reading_companion':
        return l.aiSkillReadingCompanionDesc;
      case 'seminar_mode':
        return l.aiSkillSeminarModeDesc;
      default:
        return null;
    }
  }

  bool _hasWebSearchApiKey() {
    try {
      final config = Prefs().getAiConfig(Prefs().selectedAiService);
      final key = config['webSearchApiKey']?.trim() ?? '';
      return key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _showWebSearchApiKeyDialog(BuildContext context) {
    final config = Prefs().getAiConfig(Prefs().selectedAiService);
    final controller = TextEditingController(
      text: config['webSearchApiKey'] ?? '',
    );

    final l = L10n.of(context);
    PTDialog.show<void>(
      context,
      title: l.settingsAiWebSearch,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsAiWebSearchDialogDesc,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l.settingsAiWebSearchKeyLabel,
              hintText: l.settingsAiWebSearchKeyHint,
            ),
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: L10n.of(context).commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        PTDialogAction(
          label: L10n.of(context).commonSave,
          isDefault: true,
          onPressed: () {
            final updated = Map<String, String>.from(config);
            final key = controller.text.trim();
            if (key.isEmpty) {
              updated.remove('webSearchApiKey');
            } else {
              updated['webSearchApiKey'] = key;
            }
            Prefs().saveAiConfig(Prefs().selectedAiService, updated);
            setState(() {});
            Navigator.pop(context);
          },
        ),
      ],
    ).then((_) => controller.dispose());
  }

  void _showLocalEmbeddingDialog(BuildContext context) {
    final endpointController = TextEditingController(
      text: Prefs().localEmbeddingEndpoint ?? '',
    );
    final modelController = TextEditingController(
      text: Prefs().localEmbeddingModel,
    );

    final l = L10n.of(context);
    PTDialog.show<void>(
      context,
      title: l.settingsAiLocalEmbedding,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsAiLocalEmbeddingDialogDesc,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: endpointController,
            decoration: InputDecoration(
              labelText: l.settingsAiLocalEmbeddingEndpointLabel,
              hintText: l.settingsAiLocalEmbeddingEndpointHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: modelController,
            decoration: InputDecoration(
              labelText: l.settingsAiLocalEmbeddingModelLabel,
              hintText: l.settingsAiLocalEmbeddingModelHint,
            ),
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: L10n.of(context).commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        if ((Prefs().localEmbeddingEndpoint ?? '').isNotEmpty)
          PTDialogAction(
            label: L10n.of(context).commonReset,
            onPressed: () {
              Prefs().localEmbeddingEndpoint = null;
              Prefs().localEmbeddingModel = 'nomic-embed-text';
              setState(() {});
              Navigator.pop(context);
            },
          ),
        PTDialogAction(
          label: L10n.of(context).commonSave,
          isDefault: true,
          onPressed: () {
            Prefs().localEmbeddingEndpoint = endpointController.text;
            Prefs().localEmbeddingModel = modelController.text.isEmpty
                ? 'nomic-embed-text'
                : modelController.text;
            setState(() {});
            Navigator.pop(context);
          },
        ),
      ],
    ).then((_) {
      endpointController.dispose();
      modelController.dispose();
    });
  }

  // User prompts management methods
  AbstractSettingsTile userPromptsTile() {
    final userPrompts = ref.watch(userPromptsProvider);
    ref.read(userPromptsProvider.notifier);

    return CustomSettingsTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top button and hint
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnxButton(
                  onPressed: _showAddPromptDialog,
                  child: Text(L10n.of(context).settingsAiUserPromptsAdd),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: ClaudePalette.secondary(context)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        L10n.of(context).settingsAiUserPromptsHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: ClaudePalette.secondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Prompts list
          if (userPrompts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  L10n.of(context).settingsAiUserPromptsEmpty,
                  style: TextStyle(color: ClaudePalette.secondary(context)),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: userPrompts.length,
              itemBuilder: (context, index) {
                final prompt = userPrompts[index];
                final isExpanded = _expandedUserPromptId == prompt.id;

                return _buildUserPromptItem(
                  prompt,
                  isExpanded,
                  index,
                  userPrompts.length,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserPromptItem(
    prompt,
    bool isExpanded,
    int index,
    int totalCount,
  ) {
    final notifier = ref.read(userPromptsProvider.notifier);

    // Initialize controllers
    _userPromptNameControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.name),
    );
    _userPromptContentControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.content),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: MorandiPalette.divider(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: Switch + Name + Action buttons
            Row(
              children: [
                Switch(
                  value: prompt.enabled,
                  onChanged: (_) {
                    notifier.toggleEnabled(prompt.id);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prompt.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Edit button
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.edit),
                  onPressed: () {
                    setState(() {
                      _expandedUserPromptId = isExpanded ? null : prompt.id;
                    });
                  },
                  tooltip: L10n.of(context).commonEdit,
                ),

                // Move up button
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: index > 0
                      ? () => notifier.movePrompt(prompt.id, true)
                      : null,
                ),

                // Move down button
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  onPressed: index < totalCount - 1
                      ? () => notifier.movePrompt(prompt.id, false)
                      : null,
                ),
              ],
            ),

            // Expanded edit area
            if (isExpanded) ...[
              const Divider(height: 16),
              _buildEditForm(prompt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(prompt) {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = _userPromptNameControllers[prompt.id]!;
    final contentController = _userPromptContentControllers[prompt.id]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name input
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsName,
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        const SizedBox(height: 12),

        // Content input
        TextField(
          controller: contentController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsContent,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 8,
          minLines: 5,
          maxLength: 20000,
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Delete button (uses default L10n text)
            DeleteConfirm(
              delete: () {
                notifier.deletePrompt(prompt.id);
                _userPromptNameControllers.remove(prompt.id)?.dispose();
                _userPromptContentControllers.remove(prompt.id)?.dispose();
                setState(() {
                  _expandedUserPromptId = null;
                });
              },
              useTextButton: true,
            ),

            // Save button
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                final content = contentController.text.trim();

                if (name.isEmpty || content.isEmpty) {
                  AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                  return;
                }

                final updatedPrompt = prompt.copyWith(
                  name: name,
                  content: content,
                );
                notifier.updatePrompt(updatedPrompt);

                setState(() {
                  _expandedUserPromptId = null;
                });

                AnxToast.show(L10n.of(context).commonSaveSuccess);
              },
              child: Text(L10n.of(context).commonSave),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddPromptDialog() {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = TextEditingController();
    final contentController = TextEditingController();

    SmartDialog.show(
      builder: (context) => PTDialog(
        title: L10n.of(context).settingsAiUserPromptsAdd,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsName,
                ),
                maxLength: 50,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsContent,
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 5,
                maxLength: 20000,
              ),
            ],
          ),
        ),
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () {
              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();
            },
          ),
          PTDialogAction(
            label: L10n.of(context).commonConfirm,
            isDefault: true,
            onPressed: () {
              final name = nameController.text.trim();
              final content = contentController.text.trim();

              if (name.isEmpty || content.isEmpty) {
                AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                return;
              }

              notifier.addPrompt(name: name, content: content);

              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();

              AnxToast.show(L10n.of(context).commonAddSuccess);
            },
          ),
        ],
      ),
    );
  }
}
