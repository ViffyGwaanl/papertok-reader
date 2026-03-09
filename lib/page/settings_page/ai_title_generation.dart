import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
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

    final result = await showDialog<_PromptEditResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Title prompt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Customize how automatic conversation titles are generated. '
                'You can use {{preferredLanguage}} and {{maxChars}} as variables.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter title generation prompt',
                ),
                maxLines: 10,
                minLines: 6,
                maxLength: 8000,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _PromptEditResult.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _PromptEditResult.reset),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _PromptEditResult.save),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
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
      AnxToast.show('No AI provider configured');
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          children: [
            ListTile(
              title: const Text('Follow current chat provider'),
              subtitle: const Text(
                'Use the same provider as the active chat session.',
              ),
              trailing: Prefs().aiTitleProviderId.trim().isEmpty
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Prefs().aiTitleProviderId = '';
                Navigator.pop(context);
                setState(() {});
              },
            ),
            const Divider(height: 1),
            for (final p in enabledProviders)
              ListTile(
                title: Text(p.name),
                subtitle: Text(_providerTypeLabel(context, p.type)),
                trailing: (Prefs().aiTitleProviderIdEffective == p.id &&
                        Prefs().aiTitleProviderId.trim().isNotEmpty)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
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
      AnxToast.show('No AI provider configured');
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
                  AnxToast.show('No AI provider configured');
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
                AnxToast.show('Failed to fetch models');
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
                    title: const Text('Follow provider default model'),
                    subtitle: const Text(
                      'Use the provider default model for title generation.',
                    ),
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
                    title: const Text('Custom model'),
                    subtitle: const Text(
                      'Manually enter a model id for title generation.',
                    ),
                    onTap: () async {
                      final controller = TextEditingController(
                        text: Prefs().aiTitleModel.trim(),
                      );

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Custom title model'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                hintText: 'Enter model id',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Confirm'),
                              ),
                            ],
                          );
                        },
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
                    title: const Text('Refresh models'),
                    onTap: refresh,
                  ),
                  const Divider(height: 1),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No cached models yet. Pull the provider model list first.',
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
    double tempValue = Prefs().aiTitleMaxChars.toDouble();
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Maximum title length'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Current limit: ${tempValue.round()} characters'),
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempValue.round()),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      Prefs().aiTitleMaxChars = result;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProviderId = Prefs().aiTitleProviderIdEffective;
    final providerMeta = Prefs().getAiProviderMeta(effectiveProviderId);
    final providerName = providerMeta?.name ?? effectiveProviderId;

    final model = Prefs().aiTitleModel.trim();
    final modelLabel = model.isEmpty ? 'Follow provider default' : model;
    final promptCustom = Prefs().aiTitlePrompt.trim();
    final promptLabel =
        promptCustom.isEmpty ? 'Default prompt' : 'Custom prompt';

    return settingsSections(
      sections: [
        SettingsSection(
          title: const Text('Conversation titles'),
          tiles: [
            SettingsTile.switchTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Automatic conversation titles'),
              description: const Text(
                'Generate a short chat title after the first assistant reply.',
              ),
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
              title: const Text('Title provider'),
              value: Text(providerName.isEmpty ? 'Not set' : providerName),
              description: const Text(
                'Choose which provider handles automatic title generation.',
              ),
              onPressed: (_) => _pickProvider(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Title model'),
              value: Text(modelLabel),
              description: const Text(
                'Pick a dedicated model for naming conversations.',
              ),
              onPressed: (_) => _pickModel(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.short_text_outlined),
              title: const Text('Maximum title length'),
              value: Text('${Prefs().aiTitleMaxChars} chars'),
              description: const Text(
                'Keep generated titles short and easy to scan in history.',
              ),
              onPressed: (_) => _editMaxTitleLength(),
            ),
            SettingsTile.navigation(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Title prompt'),
              value: Text(promptLabel),
              description: const Text(
                'Customize the prompt and let it adapt to the current language, such as Chinese.',
              ),
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
