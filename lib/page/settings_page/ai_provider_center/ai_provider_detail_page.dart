import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_api_key_entry.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_models_service.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class AiProviderDetailPage extends StatefulWidget {
  const AiProviderDetailPage({
    super.key,
    required this.provider,
    this.builtInOption,
  });

  final AiProviderMeta provider;
  final AiServiceOption? builtInOption;

  @override
  State<AiProviderDetailPage> createState() => _AiProviderDetailPageState();
}

class _AiProviderDetailPageState extends State<AiProviderDetailPage> {
  late AiProviderMeta _provider;

  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;

  // Managed API keys list (local-only secrets).
  late List<AiApiKeyEntry> _apiKeys;
  String _lastApiKeysRaw = '';
  bool _revealKeys = false;

  // Auto-save (debounced) to avoid requiring explicit Save taps for key changes.
  Timer? _autoSaveDebounce;

  bool _includeThoughts = true;

  bool _responsesUsePreviousResponseId = true;

  bool _isFetchingModels = false;
  List<String> _cachedModels = const [];

  // API key failover/cooldown policy (per provider).
  int _apiKeyFailureThreshold = 3;
  int _apiKeyAuthCooldownMinutes = 60;
  int _apiKeyRateLimitCooldownMinutes = 5;
  int _apiKeyServiceCooldownMinutes = 1;

  @override
  void initState() {
    super.initState();

    _provider = widget.provider;

    _nameController = TextEditingController(text: _provider.name.trim());

    final stored = Prefs().getAiConfig(_provider.id);
    _urlController = TextEditingController(
      text: (stored['url'] ?? widget.builtInOption?.defaultUrl ?? '').trim(),
    );
    _modelController = TextEditingController(
      text:
          (stored['model'] ?? widget.builtInOption?.defaultModel ?? '').trim(),
    );
    _apiKeys = _decodeApiKeysFromStored(stored);
    _lastApiKeysRaw = (stored['api_keys'] ?? '').trim();

    if (_provider.type == AiProviderType.gemini) {
      final raw = (stored['include_thoughts'] ?? 'true').trim().toLowerCase();
      _includeThoughts = raw != 'false' && raw != '0' && raw != 'no';
    } else {
      final raw = (stored['include_thoughts'] ?? 'false').trim().toLowerCase();
      _includeThoughts = raw == 'true' || raw == '1' || raw == 'yes';
    }

    if (_provider.type == AiProviderType.openaiResponses) {
      final raw = (stored['responses_use_previous_response_id'] ?? 'true')
          .trim()
          .toLowerCase();
      _responsesUsePreviousResponseId =
          raw != 'false' && raw != '0' && raw != 'no';
    }

    int parseInt(String key, int fallback) {
      final v = (stored[key] ?? '').trim();
      if (v.isEmpty) return fallback;
      return int.tryParse(v) ?? fallback;
    }

    _apiKeyFailureThreshold =
        parseInt('api_key_policy_failure_threshold', 3).clamp(1, 10);
    _apiKeyAuthCooldownMinutes =
        parseInt('api_key_policy_auth_cooldown_min', 60).clamp(1, 24 * 60);
    _apiKeyRateLimitCooldownMinutes =
        parseInt('api_key_policy_rate_limit_cooldown_min', 5).clamp(1, 24 * 60);
    _apiKeyServiceCooldownMinutes =
        parseInt('api_key_policy_service_cooldown_min', 1).clamp(1, 24 * 60);

    final modelsCache = Prefs().getAiModelsCacheV1(_provider.id);
    _cachedModels = modelsCache?.models ?? const [];

    // Auto-save for text fields.
    _urlController.addListener(_scheduleAutoSave);
    _modelController.addListener(_scheduleAutoSave);
    if (!_provider.isBuiltIn) {
      _nameController.addListener(_scheduleAutoSave);
    }

    // Keep local state in sync with runtime-updated stats (failure counters,
    // cooldown, active key) written back to Prefs.
    Prefs().addListener(_handlePrefsChange);
  }

  void _handlePrefsChange() {
    if (!mounted) return;
    final stored = Prefs().getAiConfig(_provider.id);
    final raw = (stored['api_keys'] ?? '').trim();
    if (raw == _lastApiKeysRaw) return;
    _lastApiKeysRaw = raw;
    setState(() {
      _apiKeys = _decodeApiKeysFromStored(stored);
    });
  }

  @override
  void dispose() {
    _autoSaveDebounce?.cancel();
    try {
      Prefs().removeListener(_handlePrefsChange);
    } catch (_) {}
    _nameController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  List<AiApiKeyEntry> _decodeApiKeysFromStored(Map<String, String> stored) {
    final rawMulti = (stored['api_keys'] ?? '').trim();
    if (rawMulti.isNotEmpty) {
      // JSON array of entries.
      if (rawMulti.startsWith('[')) {
        try {
          final decoded = jsonDecode(rawMulti);
          if (decoded is List) {
            final list = <AiApiKeyEntry>[];
            for (final item in decoded) {
              if (item is Map) {
                final entry = AiApiKeyEntry.fromJson(
                  item.cast<String, dynamic>(),
                );
                if (entry.key.trim().isNotEmpty) {
                  list.add(entry);
                }
              }
            }
            if (list.isNotEmpty) return list;
          }
        } catch (_) {
          // fallthrough
        }
      }

      // Legacy multi-line/comma/semicolon input.
      final parts = rawMulti
          .replaceAll('\r', '\n')
          .split(RegExp(r'[\n,;，；]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (parts.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return parts
            .toSet()
            .map(
              (k) => AiApiKeyEntry(
                id: _uuid.v4(),
                name: 'Key',
                key: k,
                enabled: true,
                createdAt: now,
                updatedAt: now,
              ),
            )
            .toList(growable: false);
      }
    }

    // Fallback: single api_key.
    final single = (stored['api_key'] ?? '').trim();
    if (single.isEmpty) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      AiApiKeyEntry(
        id: _uuid.v4(),
        name: 'Key 1',
        key: single,
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  String _encodeApiKeys() {
    return encodeAiApiKeyEntries(_apiKeys);
  }

  String _activeApiKey() {
    // Prefer the last active key stored in config (updated by runtime rotation
    // on success), so list order does NOT imply priority.
    final stored = Prefs().getAiConfig(_provider.id);
    final hint = (stored['api_key'] ?? '').trim();
    if (hint.isNotEmpty) {
      for (final e in _apiKeys) {
        if (e.enabled && e.key.trim() == hint) {
          return hint;
        }
      }
    }

    for (final e in _apiKeys) {
      if (e.enabled && e.key.trim().isNotEmpty) return e.key.trim();
    }
    return '';
  }

  Map<String, String> _buildConfigMap() {
    final map = <String, String>{
      'url': _urlController.text.trim(),
      'model': _modelController.text.trim(),
    };

    // Keys are local-only secrets.
    if (_apiKeys.isNotEmpty) {
      map['api_keys'] = _encodeApiKeys();
      map['api_key'] = _activeApiKey();
    } else {
      map['api_key'] = '';
    }

    // Gemini thinking-related configuration.
    // Default is enabled (per user preference).
    if (_provider.type == AiProviderType.gemini) {
      map['include_thoughts'] = _includeThoughts ? 'true' : 'false';
    }

    // Responses API continuation policy (non-secret).
    if (_provider.type == AiProviderType.openaiResponses) {
      map['responses_use_previous_response_id'] =
          _responsesUsePreviousResponseId ? 'true' : 'false';
    }

    // Multi-key policy (non-secret).
    map['api_key_policy_failure_threshold'] =
        _apiKeyFailureThreshold.clamp(1, 10).toString();
    map['api_key_policy_auth_cooldown_min'] =
        _apiKeyAuthCooldownMinutes.clamp(1, 24 * 60).toString();
    map['api_key_policy_rate_limit_cooldown_min'] =
        _apiKeyRateLimitCooldownMinutes.clamp(1, 24 * 60).toString();
    map['api_key_policy_service_cooldown_min'] =
        _apiKeyServiceCooldownMinutes.clamp(1, 24 * 60).toString();

    return map;
  }

  void _persist({required bool showSnackBar}) {
    final l10n = L10n.of(context);

    final map = _buildConfigMap();
    Prefs().saveAiConfig(_provider.id, map);

    if (!_provider.isBuiltIn) {
      final name = _nameController.text.trim();
      if (name.isNotEmpty && name != _provider.name) {
        final updated = _provider.copyWith(
          name: name,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        Prefs().upsertAiProviderMeta(updated);
        _provider = updated;
      }
    }

    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonSaved)),
      );
    }
  }

  void _save() {
    _persist(showSnackBar: true);
    setState(() {});
  }

  void _scheduleAutoSave() {
    _autoSaveDebounce?.cancel();
    _autoSaveDebounce = Timer(
      const Duration(milliseconds: 450),
      () {
        if (!mounted) return;
        _persist(showSnackBar: false);
      },
    );
  }

  void _applyAsDefault() {
    final l10n = L10n.of(context);
    if (!_provider.enabled) {
      return;
    }
    Prefs().selectedAiService = _provider.id;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.settingsAiProviderCenterDefaultApplied(_provider.name),
        ),
      ),
    );
  }

  String _fallbackProviderId(List<AiProviderMeta> providers) {
    for (final p in providers) {
      if (p.id == 'openai' && p.enabled) return p.id;
    }
    for (final p in providers) {
      if (p.enabled) return p.id;
    }
    return 'openai';
  }

  Future<void> _fetchModels() async {
    final l10n = L10n.of(context);

    if (_isFetchingModels) return;

    setState(() {
      _isFetchingModels = true;
    });

    try {
      final models = await AiModelsService.fetchModels(
        provider: _provider,
        rawConfig: _buildConfigMap(),
      );

      if (!mounted) return;

      if (models.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.settingsAiProviderCenterFetchModelsEmpty)),
        );
      } else {
        Prefs().saveAiModelsCacheV1(_provider.id, models);
        _cachedModels = models;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n
                  .settingsAiProviderCenterFetchModelsSuccess(models.length))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.commonFailed}: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isFetchingModels = false;
      });
    }
  }

  Future<void> _deleteProvider() async {
    final l10n = L10n.of(context);

    if (_provider.isBuiltIn) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsAiProviderCenterDeleteTitle),
          content: Text(
            l10n.settingsAiProviderCenterDeleteBody(_provider.name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;

    final wasSelected = Prefs().selectedAiService == _provider.id;

    Prefs().deleteAiProviderMeta(_provider.id);
    Prefs().deleteAiConfig(_provider.id);

    if (wasSelected) {
      Prefs().selectedAiService = _fallbackProviderId(Prefs().aiProvidersV1);
    }

    Navigator.of(context).pop();
  }

  void _setApiKeys(List<AiApiKeyEntry> next) {
    setState(() {
      _apiKeys = next;
    });
    _scheduleAutoSave();
  }

  Future<void> _showEditKeyDialog({AiApiKeyEntry? existing}) async {
    final l10n = L10n.of(context);
    final nameController = TextEditingController(text: existing?.name ?? '');
    final keyController = TextEditingController(text: existing?.key ?? '');
    bool enabled = existing?.enabled ?? true;
    bool obscure = true;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setInner) {
              return AlertDialog(
                title: Text(existing == null ? 'Add API Key' : 'Edit API Key'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Name (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: keyController,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Key',
                          suffixIcon: IconButton(
                            onPressed: () => setInner(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                            ),
                          ),
                        ),
                        maxLines: 3,
                        minLines: 1,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enabled'),
                        value: enabled,
                        onChanged: (v) => setInner(() => enabled = v),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Security: API keys are stored locally only. They are NOT synced via WebDAV and are excluded from plain backups.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l10n.commonSave),
                  ),
                ],
              );
            },
          );
        },
      );

      if (ok != true || !mounted) return;

      final key = keyController.text.trim();
      if (key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.commonFailed}: empty key')),
        );
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final name = nameController.text.trim();

      final updated = existing == null
          ? AiApiKeyEntry(
              id: _uuid.v4(),
              name: name.isEmpty ? 'Key ${_apiKeys.length + 1}' : name,
              key: key,
              enabled: enabled,
              createdAt: now,
              updatedAt: now,
            )
          : existing.copyWith(
              name: name.isEmpty ? existing.name : name,
              key: key,
              enabled: enabled,
              updatedAt: now,
            );

      final next = [..._apiKeys];
      final idx =
          existing == null ? -1 : next.indexWhere((e) => e.id == existing.id);
      if (idx == -1) {
        next.add(updated);
      } else {
        next[idx] = updated;
      }

      _setApiKeys(next);
    } finally {
      nameController.dispose();
      keyController.dispose();
    }
  }

  Future<void> _showBulkImportDialog() async {
    final l10n = L10n.of(context);
    final controller = TextEditingController();

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Import API Keys'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'Paste keys here (one per line / separated by comma/semicolon)',
              ),
              minLines: 4,
              maxLines: 10,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.commonConfirm),
              ),
            ],
          );
        },
      );

      if (ok != true || !mounted) return;

      final raw = controller.text.trim();
      if (raw.isEmpty) return;

      final parts = raw
          .replaceAll('\r', '\n')
          .split(RegExp(r'[\n,;，；]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);

      if (parts.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final existingKeys = _apiKeys.map((e) => e.key.trim()).toSet();

      final next = [..._apiKeys];
      var added = 0;
      for (final k in parts.toSet()) {
        if (existingKeys.contains(k)) continue;
        next.add(
          AiApiKeyEntry(
            id: _uuid.v4(),
            name: 'Key ${next.length + 1}',
            key: k,
            enabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        added++;
      }

      _setApiKeys(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $added key(s)')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteKey(AiApiKeyEntry entry) async {
    final l10n = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(
            'Delete ${entry.name.isEmpty ? entry.maskedKey() : entry.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    _setApiKeys(
        _apiKeys.where((e) => e.id != entry.id).toList(growable: false));
  }

  void _clearCooldownForKey(AiApiKeyEntry entry) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _setApiKeys(
      _apiKeys
          .map(
            (e) => e.id == entry.id
                ? e.copyWith(
                    consecutiveFailures: 0,
                    disabledUntil: null,
                    updatedAt: now,
                  )
                : e,
          )
          .toList(growable: false),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cooldown cleared')),
    );
  }

  void _resetStatsForKey(AiApiKeyEntry entry) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _setApiKeys(
      _apiKeys
          .map(
            (e) => e.id == entry.id
                ? e.copyWith(
                    successCount: 0,
                    failureCount: 0,
                    consecutiveFailures: 0,
                    disabledUntil: null,
                    updatedAt: now,
                  )
                : e,
          )
          .toList(growable: false),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stats reset')),
    );
  }

  Future<void> _testKey(AiApiKeyEntry entry) async {
    final l10n = L10n.of(context);

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final cfg = _buildConfigMap();
      cfg.remove('api_keys');
      cfg['api_key'] = entry.key.trim();

      final models = await AiModelsService.fetchModels(
        provider: _provider,
        rawConfig: cfg,
      );

      if (!mounted) return;

      final msg = models.isEmpty ? 'OK' : 'OK (${models.length} models)';
      _setApiKeys(
        _apiKeys
            .map(
              (e) => e.id == entry.id
                  ? e.copyWith(
                      lastTestAt: now,
                      lastTestOk: true,
                      lastTestMessage: msg,
                      updatedAt: now,
                    )
                  : e,
            )
            .toList(growable: false),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test success: ${entry.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      _setApiKeys(
        _apiKeys
            .map(
              (k) => k.id == entry.id
                  ? k.copyWith(
                      lastTestAt: now,
                      lastTestOk: false,
                      lastTestMessage: e.toString(),
                      updatedAt: now,
                    )
                  : k,
            )
            .toList(growable: false),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.commonFailed}: $e')),
      );
    }
  }

  Future<void> _testAllEnabledKeys() async {
    for (final k in _apiKeys) {
      if (!k.enabled) continue;
      await _testKey(k);
    }
  }

  Widget _buildApiKeysSection(L10n l10n) {
    final activeKey = _activeApiKey();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'API Keys',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Import',
              onPressed: _showBulkImportDialog,
              icon: const Icon(Icons.playlist_add),
            ),
            IconButton(
              tooltip: 'Add',
              onPressed: () => _showEditKeyDialog(),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Test',
              onPressed: _testAllEnabledKeys,
              icon: const Icon(Icons.check_circle_outline),
            ),
            IconButton(
              tooltip: _revealKeys ? 'Hide' : 'Reveal',
              onPressed: () => setState(() => _revealKeys = !_revealKeys),
              icon: Icon(_revealKeys ? Icons.visibility_off : Icons.visibility),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Keys are stored locally only (not synced via WebDAV; excluded from plain backups).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_apiKeys.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('No API keys configured.'),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _apiKeys.map((e) {
                final isActive = e.enabled && e.key.trim() == activeKey;
                final subtitle = _revealKeys
                    ? e.key.trim()
                    : (e.maskedKey().isEmpty ? '••••' : e.maskedKey());

                final testText = e.lastTestAt == null
                    ? ''
                    : (e.lastTestOk == true
                        ? ' • last test: OK'
                        : ' • last test: FAIL');

                final fails = e.failureCount ?? 0;
                final consec = e.consecutiveFailures ?? 0;
                final failText = fails > 0
                    ? ' • fails: $fails${consec > 0 ? ' (x$consec)' : ''}'
                    : '';

                final nowMs = DateTime.now().millisecondsSinceEpoch;
                final cooldownUntil = e.disabledUntil;
                final inCooldown =
                    cooldownUntil != null && cooldownUntil > nowMs;
                final cooldownText = inCooldown ? ' • cooldown' : '';

                return Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.key,
                        color: e.enabled
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                      ),
                      title: Text(
                        '${e.name}${isActive ? ' (active)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$subtitle$testText$failText$cooldownText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _showEditKeyDialog(existing: e),
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: e.key.trim()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Key copied')),
                        );
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Test',
                            onPressed: () => _testKey(e),
                            icon: const Icon(Icons.play_circle_outline),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'copy':
                                  Clipboard.setData(
                                    ClipboardData(text: e.key.trim()),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Key copied')),
                                  );
                                  break;
                                case 'clear_cooldown':
                                  _clearCooldownForKey(e);
                                  break;
                                case 'reset_stats':
                                  _resetStatsForKey(e);
                                  break;
                                case 'delete':
                                  _deleteKey(e);
                                  break;
                                default:
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Copy'),
                              ),
                              const PopupMenuItem(
                                value: 'clear_cooldown',
                                child: Text('解除冷却'),
                              ),
                              const PopupMenuItem(
                                value: 'reset_stats',
                                child: Text('重置统计'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.commonDelete),
                              ),
                            ],
                          ),
                          Switch.adaptive(
                            value: e.enabled,
                            onChanged: (v) {
                              final now = DateTime.now().millisecondsSinceEpoch;
                              _setApiKeys(
                                _apiKeys
                                    .map(
                                      (k) => k.id == e.id
                                          ? k.copyWith(
                                              enabled: v,
                                              updatedAt: now,
                                            )
                                          : k,
                                    )
                                    .toList(growable: false),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (e.id != _apiKeys.last.id) const Divider(height: 1),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('高级策略'),
          subtitle: const Text('失败阈值 / 冷却时间（对话+翻译共用）'),
          children: [
            DropdownButtonFormField<int>(
              value: _apiKeyFailureThreshold,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '连续失败阈值',
              ),
              items: const [1, 2, 3, 4, 5, 6, 8, 10]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _apiKeyFailureThreshold = v);
                _scheduleAutoSave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _apiKeyAuthCooldownMinutes,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '401/鉴权失败 冷却(分钟)',
              ),
              items: const [1, 5, 10, 30, 60, 120, 360]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _apiKeyAuthCooldownMinutes = v);
                _scheduleAutoSave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _apiKeyRateLimitCooldownMinutes,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '429/限流 冷却(分钟)',
              ),
              items: const [1, 2, 5, 10, 30, 60]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _apiKeyRateLimitCooldownMinutes = v);
                _scheduleAutoSave();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _apiKeyServiceCooldownMinutes,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '503/网关/服务错误 冷却(分钟)',
              ),
              items: const [1, 2, 5, 10, 30]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _apiKeyServiceCooldownMinutes = v);
                _scheduleAutoSave();
              },
            ),
            const SizedBox(height: 8),
            Text(
              '说明：当请求在尚未产生任何流式输出前失败，并且错误被判定为可重试（401/429/503）时，会自动切换到下一把 Key；达到连续失败阈值后，当前 Key 会进入冷却。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final stored = Prefs().getAiConfig(_provider.id);
    final config = LangchainAiConfig.fromPrefs(_provider.id, stored);

    return Scaffold(
      appBar: AppBar(
        title: Text(_provider.name),
        actions: [
          if (!_provider.isBuiltIn)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.commonDelete,
              onPressed: _deleteProvider,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.commonSave,
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoRow('ID', _provider.id),
          _buildInfoRow(
            l10n.settingsAiProviderCenterProviderTypeLabel,
            _typeLabel(_provider.type, l10n),
          ),
          const SizedBox(height: 12),
          if (_provider.isBuiltIn)
            _buildInfoRow(
              l10n.settingsAiProviderCenterProviderNameLabel,
              _provider.name,
            )
          else
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.settingsAiProviderCenterProviderNameLabel,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.settingsAiProviderCenterUrlLabel,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            l10n.settingsAiProviderCenterEffectiveBaseUrlLabel,
            config.baseUrl ?? '',
          ),
          const SizedBox(height: 12),
          if (_cachedModels.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _cachedModels.contains(_modelController.text.trim())
                  ? _modelController.text.trim()
                  : null,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.settingsAiProviderCenterModelLabel,
              ),
              items: _cachedModels
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _modelController.text = v;
                });
              },
            )
          else
            TextField(
              controller: _modelController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.settingsAiProviderCenterModelLabel,
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isFetchingModels ? null : _fetchModels,
            icon: _isFetchingModels
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(l10n.settingsAiProviderCenterFetchModels),
          ),
          const SizedBox(height: 12),
          if (_provider.type == AiProviderType.gemini)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsAiProviderCenterIncludeThoughtsTitle),
              subtitle: Text(l10n.settingsAiProviderCenterIncludeThoughtsDesc),
              value: _includeThoughts,
              onChanged: (v) {
                setState(() {
                  _includeThoughts = v;
                });
                _scheduleAutoSave();
              },
            ),
          if (_provider.type == AiProviderType.gemini)
            const SizedBox(height: 12),
          if (_provider.type == AiProviderType.openaiResponses)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title:
                  Text(l10n.settingsAiProviderCenterUsePreviousResponseIdTitle),
              subtitle:
                  Text(l10n.settingsAiProviderCenterUsePreviousResponseIdDesc),
              value: _responsesUsePreviousResponseId,
              onChanged: (v) {
                setState(() {
                  _responsesUsePreviousResponseId = v;
                });
                _scheduleAutoSave();
              },
            ),
          if (_provider.type == AiProviderType.openaiResponses)
            const SizedBox(height: 12),
          _buildApiKeysSection(l10n),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _applyAsDefault,
            child: Text(l10n.settingsAiProviderCenterSetAsDefault),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  String _typeLabel(AiProviderType type, L10n l10n) {
    switch (type) {
      case AiProviderType.openaiCompatible:
        return l10n.settingsAiProviderCenterTypeOpenAICompatible;
      case AiProviderType.openaiResponses:
        return l10n.settingsAiProviderCenterTypeOpenAIResponses;
      case AiProviderType.anthropic:
        return l10n.settingsAiProviderCenterTypeAnthropic;
      case AiProviderType.gemini:
        return l10n.settingsAiProviderCenterTypeGemini;
    }
  }
}
