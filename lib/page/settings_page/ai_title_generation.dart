import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:flutter/material.dart';

class AiTitleGenerationSettingsPage extends StatefulWidget {
  const AiTitleGenerationSettingsPage({super.key});

  @override
  State<AiTitleGenerationSettingsPage> createState() =>
      _AiTitleGenerationSettingsPageState();
}

class _AiTitleGenerationSettingsPageState
    extends State<AiTitleGenerationSettingsPage> {
  late String _providerId;
  late final TextEditingController _modelController;
  late int _maxChars;
  late bool _enabled;
  bool _isFetching = false;
  List<String> _cachedModels = const [];

  @override
  void initState() {
    super.initState();
    _providerId = Prefs().aiTitleProviderIdEffective;
    _enabled = Prefs().aiTitleGenerationEnabled;
    _maxChars = Prefs().aiTitleMaxChars;
    _modelController = TextEditingController(text: Prefs().aiTitleModel);
    _loadCachedModels();
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  List<AiProviderMeta> get _enabledProviders =>
      Prefs().aiProvidersV1.where((e) => e.enabled).toList(growable: false);

  void _loadCachedModels() {
    final cache = Prefs().getAiModelsCacheV1(_providerId);
    _cachedModels = cache?.models ?? const [];
  }

  Future<void> _fetchModels() async {
    final provider = Prefs().getAiProviderMeta(_providerId);
    if (provider == null || _isFetching) {
      return;
    }

    setState(() {
      _isFetching = true;
    });

    try {
      final capabilities = await AiModelsService.fetchModelCapabilities(
        provider: provider,
        rawConfig: Prefs().getAiConfig(_providerId),
      );
      if (!mounted) return;
      Prefs().saveAiModelCapabilitiesCacheV1(_providerId, capabilities);
      Prefs().saveAiModelsCacheV1(
        _providerId,
        capabilities.map((e) => e.id).toList(growable: false),
      );
      setState(() {
        _cachedModels = capabilities.map((e) => e.id).toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fetched ${capabilities.length} models')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch models: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }
  }

  void _save() {
    Prefs().aiTitleGenerationEnabled = _enabled;
    Prefs().aiTitleProviderId = _providerId;
    Prefs().aiTitleModel = _modelController.text.trim();
    Prefs().aiTitleMaxChars = _maxChars;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved title generation settings')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final capabilities =
        Prefs().getAiModelCapabilitiesCacheV1(_providerId)?.models ?? const [];

    return SettingsSubpageScaffold(
      title: 'Title generation',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile.adaptive(
            title: const Text('Enable automatic chat titles'),
            subtitle: const Text(
              'Generate a short conversation title asynchronously after the first assistant reply.',
            ),
            value: _enabled,
            onChanged: (value) {
              setState(() {
                _enabled = value;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Title provider',
            ),
            items: _enabledProviders
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider.id,
                    child: Text(provider.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _providerId = value;
                _loadCachedModels();
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Title model',
              suffixIcon: IconButton(
                tooltip: 'Fetch models',
                onPressed: _isFetching ? null : _fetchModels,
                icon: _isFetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ),
          ),
          if (_cachedModels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cachedModels
                  .map(
                    (model) => ActionChip(
                      label: Text(model),
                      onPressed: () {
                        _modelController.text = model;
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (capabilities.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Cached model capabilities',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...capabilities.take(6).map(
                  (capability) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(capability.id),
                    subtitle: Text(
                      'context: ${capability.contextWindow ?? '-'} · output: ${capability.maxOutputTokens ?? '-'} · thinking: ${capability.supportsThinking ?? false}',
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 16),
          Text(
            'Max title length: $_maxChars',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            min: 8,
            max: 48,
            divisions: 10,
            value: _maxChars.toDouble(),
            label: '$_maxChars',
            onChanged: (value) {
              setState(() {
                _maxChars = value.round();
              });
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Recommended: use a small, fast model for titles. If no title model is set, the provider default model will be used.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
