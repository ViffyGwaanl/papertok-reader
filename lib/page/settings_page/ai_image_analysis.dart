import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/service/ai/ai_models_service.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class AiImageAnalysisSettingsPage extends StatefulWidget {
  const AiImageAnalysisSettingsPage({super.key});

  @override
  State<AiImageAnalysisSettingsPage> createState() =>
      _AiImageAnalysisSettingsPageState();
}

class _AiImageAnalysisSettingsPageState
    extends State<AiImageAnalysisSettingsPage> {
  String _providerTypeLabel(BuildContext context, AiProviderType type) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return L10n.of(context).settingsAiProviderCenterTypeOpenAICompatible;
      case AiProviderType.openaiResponses:
        return L10n.of(context).settingsAiProviderCenterTypeOpenAIResponses;
      case AiProviderType.anthropic:
        return L10n.of(context).settingsAiProviderCenterTypeAnthropic;
      case AiProviderType.gemini:
        return L10n.of(context).settingsAiProviderCenterTypeGemini;
    }
  }

  Future<void> _pickProvider() async {
    final l10n = L10n.of(context);
    final enabledProviders =
        Prefs().aiProvidersV1.where((p) => p.enabled).toList(growable: false);

    if (enabledProviders.isEmpty) {
      AnxToast.show(l10n.aiServiceNotConfigured);
      return;
    }

    final currentEffectiveId = Prefs().aiImageAnalysisProviderIdEffective;
    final currentRawId = Prefs().aiImageAnalysisProviderId;
    // Empty raw id means "follow chat provider".
    final groupValue = currentRawId.isEmpty ? '' : currentEffectiveId;

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsAiImageAnalysisProvider,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PTPickerRow<String>(
              value: '',
              groupValue: groupValue,
              title: l10n.settingsAiImageAnalysisFollowChatProvider,
              subtitle: l10n.settingsAiImageAnalysisFollowChatProviderDesc,
              leading: Icons.link_outlined,
              onChanged: (_) {
                Prefs().aiImageAnalysisProviderId = '';
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
            for (final p in enabledProviders)
              PTPickerRow<String>(
                value: p.id,
                groupValue: groupValue,
                title: p.name,
                subtitle: _providerTypeLabel(context, p.type),
                leading: Icons.extension_outlined,
                onChanged: (id) {
                  Prefs().aiImageAnalysisProviderId = id;
                  Navigator.pop(ctx);
                  setState(() {});
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickImageOpenMode() async {
    final l10n = L10n.of(context);
    final current = Prefs().aiImageOpenModeV1;

    String labelFor(String code) => code == 'tap'
        ? l10n.settingsAiImageOpenModeTap
        : l10n.settingsAiImageOpenModeLongPress;

    IconData iconFor(String code) =>
        code == 'tap' ? Icons.touch_app_outlined : Icons.swipe_outlined;

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsAiImageOpenModeTitle,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in const <String>['long_press', 'tap'])
              PTPickerRow<String>(
                value: v,
                groupValue: current,
                title: labelFor(v),
                leading: iconFor(v),
                onChanged: (val) {
                  Prefs().aiImageOpenModeV1 = val;
                  Navigator.pop(ctx);
                  setState(() {});
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _editPrompt() async {
    final l10n = L10n.of(context);
    final controller = TextEditingController(
      text: Prefs().aiImageAnalysisPrompt.trim().isEmpty
          ? Prefs().aiImageAnalysisPromptEffective
          : Prefs().aiImageAnalysisPrompt,
    );

    final result = await PTDialog.show<_PromptEditResult>(
      context,
      title: l10n.settingsAiImageAnalysisPromptTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsAiImageAnalysisPromptDesc,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.settingsAiImageAnalysisPromptHint,
            ),
            maxLines: 10,
            minLines: 6,
            maxLength: 20000,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsAiImageAnalysisPromptVariablesHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () =>
              Navigator.pop(context, _PromptEditResult.cancel),
        ),
        PTDialogAction(
          label: l10n.settingsAiImageAnalysisPromptReset,
          onPressed: () =>
              Navigator.pop(context, _PromptEditResult.reset),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () =>
              Navigator.pop(context, _PromptEditResult.save),
        ),
      ],
    );

    if (!mounted || result == null || result == _PromptEditResult.cancel) {
      controller.dispose();
      return;
    }

    if (result == _PromptEditResult.reset) {
      Prefs().aiImageAnalysisPrompt = '';
      setState(() {});
      controller.dispose();
      return;
    }

    // Save
    final value = controller.text.trim();
    final defaultValue = Prefs().aiImageAnalysisPromptEffective.trim();
    Prefs().aiImageAnalysisPrompt = (value == defaultValue) ? '' : value;
    setState(() {});
    controller.dispose();
  }

  Future<void> _pickModel() async {
    final l10n = L10n.of(context);
    final providerId = Prefs().aiImageAnalysisProviderIdEffective;
    final meta = Prefs().getAiProviderMeta(providerId);

    if (meta == null) {
      AnxToast.show(l10n.aiServiceNotConfigured);
      return;
    }

    var models = Prefs().getAiModelsCacheV1(providerId)?.models ?? const [];
    var loading = false;

    await PTBottomSheet.show<void>(
      context,
      title: l10n.settingsAiImageAnalysisModel,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> refresh() async {
              if (loading) return;
              setModalState(() {
                loading = true;
              });

              try {
                final rawConfig = Prefs().getAiConfig(providerId);
                if (rawConfig.isEmpty) {
                  AnxToast.show(l10n.aiServiceNotConfigured);
                  return;
                }

                final fetched = await AiModelsService.fetchModels(
                  provider: meta,
                  rawConfig: rawConfig,
                );

                if (fetched.isNotEmpty) {
                  Prefs().saveAiModelsCacheV1(providerId, fetched);
                }

                models = fetched;
              } catch (_) {
                AnxToast.show(l10n.commonFailed);
              } finally {
                setModalState(() {
                  loading = false;
                });
              }
            }

            final currentModel = Prefs().aiImageAnalysisModel.trim();

            Future<void> openCustomModelDialog() async {
              final controller = TextEditingController(text: currentModel);

              final ok = await PTDialog.show<bool>(
                context,
                title: l10n.settingsAiImageAnalysisModelCustom,
                content: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: l10n.settingsAiImageAnalysisModelCustomHint,
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
                Prefs().aiImageAnalysisModel = controller.text;
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                setState(() {});
              }
              controller.dispose();
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PTPickerRow<String>(
                    value: '',
                    groupValue: currentModel,
                    title:
                        l10n.settingsAiImageAnalysisModelFollowProvider,
                    subtitle:
                        l10n.settingsAiImageAnalysisModelFollowProviderDesc,
                    leading: Icons.link_outlined,
                    onChanged: (_) {
                      Prefs().aiImageAnalysisModel = '';
                      Navigator.pop(ctx);
                      setState(() {});
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.edit_outlined,
                      color: ClaudePalette.secondary(context),
                    ),
                    title:
                        Text(l10n.settingsAiImageAnalysisModelCustom),
                    subtitle: Text(
                        l10n.settingsAiImageAnalysisModelCustomDesc),
                    onTap: openCustomModelDialog,
                  ),
                  ListTile(
                    leading: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : Icon(
                            Icons.refresh,
                            color: ClaudePalette.secondary(context),
                          ),
                    title: Text(l10n.commonRefresh),
                    onTap: refresh,
                  ),
                  Divider(
                    height: 1,
                    color: ClaudePalette.divider(context),
                  ),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.settingsAiImageAnalysisModelEmpty,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final m in models)
                    PTPickerRow<String>(
                      value: m,
                      groupValue: currentModel,
                      title: m,
                      onChanged: (val) {
                        Prefs().aiImageAnalysisModel = val;
                        Navigator.pop(ctx);
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

  @override
  Widget build(BuildContext context) {
    final effectiveProviderId = Prefs().aiImageAnalysisProviderIdEffective;
    final providerMeta = Prefs().getAiProviderMeta(effectiveProviderId);
    final providerName = providerMeta?.name ?? effectiveProviderId;

    final model = Prefs().aiImageAnalysisModel.trim();
    final modelLabel = model.isEmpty
        ? L10n.of(context).settingsAiImageAnalysisModelFollowProviderShort
        : model;

    final promptCustom = Prefs().aiImageAnalysisPrompt.trim();
    final promptLabel = promptCustom.isEmpty
        ? L10n.of(context).settingsAiImageAnalysisPromptDefaultShort
        : L10n.of(context).settingsAiImageAnalysisPromptCustomShort;
    final imageOpenMode = Prefs().aiImageOpenModeV1;
    final imageOpenModeLabel = imageOpenMode == 'tap'
        ? L10n.of(context).settingsAiImageOpenModeTap
        : L10n.of(context).settingsAiImageOpenModeLongPress;
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsAiImageAnalysisTitle),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.hub_outlined),
              title: Text(L10n.of(context).settingsAiImageAnalysisProvider),
              value: Text(providerName.isEmpty
                  ? L10n.of(context).commonNotSet
                  : providerName),
              description:
                  Text(L10n.of(context).settingsAiImageAnalysisProviderDesc),
              onPressed: (_) => _pickProvider(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(L10n.of(context).settingsAiImageAnalysisModel),
              value: Text(modelLabel),
              description:
                  Text(L10n.of(context).settingsAiImageAnalysisModelDesc),
              onPressed: (_) => _pickModel(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.touch_app_outlined),
              title: Text(L10n.of(context).settingsAiImageOpenModeTitle),
              value: Text(imageOpenModeLabel),
              description: Text(L10n.of(context).settingsAiImageOpenModeDesc),
              onPressed: (_) => _pickImageOpenMode(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.edit_note_outlined),
              title: Text(L10n.of(context).settingsAiImageAnalysisPrompt),
              value: Text(promptLabel),
              description:
                  Text(L10n.of(context).settingsAiImageAnalysisPromptDescTile),
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
