import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class AiTitleGenerationSettingsPage extends StatefulWidget {
  const AiTitleGenerationSettingsPage({super.key});

  @override
  State<AiTitleGenerationSettingsPage> createState() =>
      _AiTitleGenerationSettingsPageState();
}

class _AiTitleGenerationSettingsPageState
    extends State<AiTitleGenerationSettingsPage> {
  Future<void> _editPrompt() async {
    final controller = TextEditingController(
      text: Prefs().aiTitlePrompt.trim().isEmpty
          ? Prefs().aiTitlePromptEffective
          : Prefs().aiTitlePrompt,
    );

    final l10n = L10n.of(context);
    final result = await PTDialog.show<_PromptEditResult>(
      context,
      title: l10n.aiTitlePromptDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.aiTitlePromptDialogDesc,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: l10n.aiTitlePromptHint,
            ),
            maxLines: 10,
            minLines: 6,
            maxLength: 8000,
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context, _PromptEditResult.cancel),
        ),
        PTDialogAction(
          label: l10n.commonReset,
          onPressed: () => Navigator.pop(context, _PromptEditResult.reset),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () => Navigator.pop(context, _PromptEditResult.save),
        ),
      ],
    );

    if (!mounted || result == null || result == _PromptEditResult.cancel) {
      controller.dispose();
      return;
    }

    if (result == _PromptEditResult.reset) {
      Prefs().aiTitlePrompt = '';
      setState(() {});
      controller.dispose();
      return;
    }

    final value = controller.text.trim();
    final defaultValue = Prefs().aiTitlePromptEffective.trim();
    Prefs().aiTitlePrompt = value == defaultValue ? '' : value;
    setState(() {});
    controller.dispose();
  }

  String _providerTypeLabel(BuildContext context, AiProviderType type) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return 'OpenAI Compatible';
      case AiProviderType.openaiResponses:
        return 'OpenAI Responses';
      case AiProviderType.anthropic:
        return 'Anthropic';
      case AiProviderType.gemini:
        return 'Gemini';
    }
  }

  Future<void> _pickProvider() async {
    final enabledProviders =
        Prefs().aiProvidersV1.where((p) => p.enabled).toList(growable: false);

    if (enabledProviders.isEmpty) {
      AnxToast.show(L10n.of(context).aiNoProviderConfigured);
      return;
    }

    final currentId = Prefs().aiTitleProviderId.trim().isEmpty
        ? ''
        : Prefs().aiTitleProviderIdEffective;

    if (!mounted) return;
    final l10n = L10n.of(context);
    await PTBottomSheet.show(
      context,
      title: l10n.aiTitleProviderPickerTitle,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PTPickerRow<String>(
              value: '',
              groupValue: currentId,
              title: l10n.aiTitleProviderFollowChat,
              subtitle: l10n.aiTitleProviderFollowChatDesc,
              onChanged: (_) {
                Prefs().aiTitleProviderId = '';
                Navigator.pop(context);
                setState(() {});
              },
            ),
            for (final p in enabledProviders)
              PTPickerRow<String>(
                value: p.id,
                groupValue: currentId,
                title: p.name,
                subtitle: _providerTypeLabel(context, p.type),
                onChanged: (_) {
                  Prefs().aiTitleProviderId = p.id;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickModel() async {
    final providerId = Prefs().aiTitleProviderIdEffective;
    final meta = Prefs().getAiProviderMeta(providerId);

    if (meta == null) {
      AnxToast.show(L10n.of(context).aiNoProviderConfigured);
      return;
    }

    var models = Prefs().getAiModelsCacheV1(providerId)?.models ?? const [];
    var capabilities =
        Prefs().getAiModelCapabilitiesCacheV1(providerId)?.models ?? const [];
    var loading = false;

    String capabilityLabel(String modelId) {
      for (final capability in capabilities) {
        if (capability.id == modelId) {
          final context = capability.contextWindow?.toString() ?? '-';
          final output = capability.maxOutputTokens?.toString() ?? '-';
          return 'ctx $context · out $output';
        }
      }
      return 'Capability unknown';
    }

    if (!mounted) return;
    final l10n = L10n.of(context);
    await PTBottomSheet.show(
      context,
      title: l10n.aiTitleModelPickerTitle,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> refresh() async {
              if (loading) return;
              setModalState(() {
                loading = true;
              });

              try {
                final rawConfig = Prefs().getAiConfig(providerId);
                if (rawConfig.isEmpty) {
                  AnxToast.show(l10n.aiNoProviderConfigured);
                  return;
                }

                final fetched = await AiModelsService.fetchModelCapabilities(
                  provider: meta,
                  rawConfig: rawConfig,
                );

                if (fetched.isNotEmpty) {
                  Prefs().saveAiModelCapabilitiesCacheV1(providerId, fetched);
                  Prefs().saveAiModelsCacheV1(
                    providerId,
                    fetched.map((e) => e.id).toList(growable: false),
                  );
                }

                capabilities = fetched;
                models = fetched.map((e) => e.id).toList(growable: false);
              } catch (_) {
                AnxToast.show(l10n.aiModelsRefreshFailed);
              } finally {
                setModalState(() {
                  loading = false;
                });
              }
            }

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: ListView(
                children: [
                  ListTile(
                    title: Text(l10n.aiTitleModelFollowDefault),
                    subtitle: Text(l10n.aiTitleModelFollowDefaultDesc),
                    trailing: Prefs().aiTitleModel.trim().isEmpty
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      Prefs().aiTitleModel = '';
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(l10n.aiTitleModelCustom),
                    subtitle: Text(l10n.aiTitleModelCustomDesc),
                    onTap: () async {
                      final controller = TextEditingController(
                        text: Prefs().aiTitleModel.trim(),
                      );

                      final ok = await PTDialog.show<bool>(
                        context,
                        title: l10n.aiTitleModelCustomDialogTitle,
                        content: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: l10n.aiTitleModelCustomHint,
                          ),
                        ),
                        actions: [
                          PTDialogAction(
                            label: l10n.commonCancel,
                            onPressed: () => Navigator.pop(context, false),
                          ),
                          PTDialogAction(
                            label: l10n.commonConfirm,
                            isDefault: true,
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ],
                      );

                      if (ok == true) {
                        Prefs().aiTitleModel = controller.text.trim();
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                        setState(() {});
                      }
                    },
                  ),
                  ListTile(
                    leading: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    title: Text(l10n.aiTitleModelRefresh),
                    onTap: refresh,
                  ),
                  const Divider(height: 1),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.aiTitleModelNoCacheHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final m in models)
                    ListTile(
                      title: Text(m),
                      subtitle: Text(capabilityLabel(m)),
                      trailing: (Prefs().aiTitleModel.trim() == m)
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        Prefs().aiTitleModel = m;
                        Navigator.pop(context);
                        setState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editMaxTitleLength() async {
    final l10n = L10n.of(context);
    double tempValue = Prefs().aiTitleMaxChars.toDouble();
    final result = await PTDialog.show<int>(
      context,
      title: l10n.aiTitleMaxLengthTitle,
      content: StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.aiTitleMaxLengthCurrent(tempValue.round())),
              const SizedBox(height: 12),
              Slider(
                min: 8,
                max: 48,
                divisions: 10,
                value: tempValue,
                label: '${tempValue.round()}',
                onChanged: (value) {
                  setDialogState(() {
                    tempValue = value;
                  });
                },
              ),
            ],
          );
        },
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () => Navigator.pop(context, tempValue.round()),
        ),
      ],
    );

    if (result != null) {
      Prefs().aiTitleMaxChars = result;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final effectiveProviderId = Prefs().aiTitleProviderIdEffective;
    final providerMeta = Prefs().getAiProviderMeta(effectiveProviderId);
    final providerName = providerMeta?.name ?? effectiveProviderId;

    final model = Prefs().aiTitleModel.trim();
    final modelLabel = model.isEmpty ? l10n.aiTitleModelDefault : model;
    final promptCustom = Prefs().aiTitlePrompt.trim();
    final promptLabel =
        promptCustom.isEmpty ? l10n.aiTitlePromptDefault : l10n.aiTitlePromptCustom;

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(l10n.settingsAiConversationTitles),
          tiles: [
            SettingsTile.switchTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.aiAutoTitleToggleTitle),
              description: Text(l10n.aiAutoTitleToggleDesc),
              initialValue: Prefs().aiTitleGenerationEnabled,
              onToggle: (value) async {
                Prefs().aiTitleGenerationEnabled = value;
                if (mounted) {
                  setState(() {});
                }
              },
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.hub_outlined),
              title: Text(l10n.aiTitleProviderPickerTitle),
              value: Text(providerName.isEmpty ? l10n.aiTitleProviderNotSet : providerName),
              description: Text(l10n.aiTitleProviderPickerDesc),
              onPressed: (_) => _pickProvider(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(l10n.aiTitleModelPickerTitle),
              value: Text(modelLabel),
              description: Text(l10n.aiTitleModelPickerDesc),
              onPressed: (_) => _pickModel(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.short_text_outlined),
              title: Text(l10n.aiTitleMaxLengthTitle),
              value: Text(l10n.aiTitleMaxLengthValue(Prefs().aiTitleMaxChars)),
              description: Text(l10n.aiTitleMaxLengthDesc),
              onPressed: (_) => _editMaxTitleLength(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(l10n.aiTitlePromptDialogTitle),
              value: Text(promptLabel),
              description: Text(l10n.aiTitlePromptTileDesc),
              onPressed: (_) => _editPrompt(),
            ),
          ],
        ),
      ],
    );
  }
}

enum _PromptEditResult {
  cancel,
  reset,
  save,
}
