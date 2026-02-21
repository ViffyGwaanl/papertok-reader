import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
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
    final enabledProviders =
        Prefs().aiProvidersV1.where((p) => p.enabled).toList(growable: false);

    if (enabledProviders.isEmpty) {
      AnxToast.show(L10n.of(context).aiServiceNotConfigured);
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            ListTile(
              title: Text(
                  L10n.of(context).settingsAiImageAnalysisFollowChatProvider),
              subtitle: Text(
                L10n.of(context).settingsAiImageAnalysisFollowChatProviderDesc,
              ),
              onTap: () {
                Prefs().aiImageAnalysisProviderId = '';
                Navigator.pop(context);
                setState(() {});
              },
            ),
            const Divider(height: 1),
            for (final p in enabledProviders)
              ListTile(
                title: Text(p.name),
                subtitle: Text(_providerTypeLabel(context, p.type)),
                trailing: (Prefs().aiImageAnalysisProviderIdEffective == p.id)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Prefs().aiImageAnalysisProviderId = p.id;
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
    final providerId = Prefs().aiImageAnalysisProviderIdEffective;
    final meta = Prefs().getAiProviderMeta(providerId);

    if (meta == null) {
      AnxToast.show(L10n.of(context).aiServiceNotConfigured);
      return;
    }

    var models = Prefs().getAiModelsCacheV1(providerId)?.models ?? const [];
    var loading = false;

    await showModalBottomSheet(
      context: context,
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
                  AnxToast.show(L10n.of(context).aiServiceNotConfigured);
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
                AnxToast.show(L10n.of(context).commonFailed);
              } finally {
                setModalState(() {
                  loading = false;
                });
              }
            }

            return SafeArea(
              child: ListView(
                children: [
                  ListTile(
                    title: Text(L10n.of(context)
                        .settingsAiImageAnalysisModelFollowProvider),
                    subtitle: Text(L10n.of(context)
                        .settingsAiImageAnalysisModelFollowProviderDesc),
                    trailing: Prefs().aiImageAnalysisModel.trim().isEmpty
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      Prefs().aiImageAnalysisModel = '';
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(
                        L10n.of(context).settingsAiImageAnalysisModelCustom),
                    subtitle: Text(
                      L10n.of(context).settingsAiImageAnalysisModelCustomDesc,
                    ),
                    onTap: () async {
                      final controller = TextEditingController(
                        text: Prefs().aiImageAnalysisModel.trim(),
                      );

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(
                              L10n.of(context)
                                  .settingsAiImageAnalysisModelCustom,
                            ),
                            content: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: L10n.of(context)
                                    .settingsAiImageAnalysisModelCustomHint,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(L10n.of(context).commonCancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(L10n.of(context).commonConfirm),
                              ),
                            ],
                          );
                        },
                      );

                      if (ok == true) {
                        Prefs().aiImageAnalysisModel = controller.text;
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
                    title: Text(L10n.of(context).commonRefresh),
                    onTap: refresh,
                  ),
                  const Divider(height: 1),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        L10n.of(context).settingsAiImageAnalysisModelEmpty,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final m in models)
                    ListTile(
                      title: Text(m),
                      trailing: (Prefs().aiImageAnalysisModel.trim() == m)
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        Prefs().aiImageAnalysisModel = m;
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

  @override
  Widget build(BuildContext context) {
    final effectiveProviderId = Prefs().aiImageAnalysisProviderIdEffective;
    final providerMeta = Prefs().getAiProviderMeta(effectiveProviderId);
    final providerName = providerMeta?.name ?? effectiveProviderId;

    final model = Prefs().aiImageAnalysisModel.trim();
    final modelLabel = model.isEmpty
        ? L10n.of(context).settingsAiImageAnalysisModelFollowProviderShort
        : model;

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
          ],
        ),
      ],
    );
  }
}
