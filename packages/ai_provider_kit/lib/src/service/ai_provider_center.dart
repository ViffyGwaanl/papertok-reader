import 'dart:convert';

import '../models/ai_model_capability.dart';
import '../models/ai_provider_meta.dart';
import '../store/ai_provider_store.dart';

/// Cached model ids for one provider, with the time they were fetched.
typedef AiModelsCacheEntry = ({int updatedAt, List<String> models});

/// Cached model capabilities for one provider.
typedef AiModelCapabilitiesCacheEntry = ({
  int updatedAt,
  List<AiModelCapability> models,
});

/// Registry, configuration and model caches for every configured provider.
///
/// This owns persistence only. Change notification and any "settings were
/// touched" bookkeeping belong to the host app, which can wrap these calls.
class AiProviderCenter {
  AiProviderCenter(this.store, {this.onDecodeError});

  final AiProviderStore store;

  /// Called when a stored value is corrupt. The center keeps working with an
  /// empty value rather than throwing, so a bad write cannot brick the app.
  final void Function(Object error, String key)? onDecodeError;

  static const String providersKey = 'aiProvidersV1';
  static const String defaultProviderKey = 'selectedAiService';
  static const String configKeyPrefix = 'aiConfig_';
  static const String modelsCacheKeyPrefix = 'aiModelsCacheV1_';
  static const String modelCapabilitiesCacheKeyPrefix =
      'aiModelCapabilitiesCacheV1_';

  /// Config entries that hold secrets.
  ///
  /// These must never be synced or written to a plain-text backup. Use
  /// [safeConfig] to strip them.
  static const Set<String> secretConfigKeys = {'api_key', 'api_keys'};

  /// [raw] without any secret entries.
  static Map<String, String> safeConfig(Map<String, String> raw) {
    return {
      for (final entry in raw.entries)
        if (!secretConfigKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  static String configKey(String identifier) => '$configKeyPrefix$identifier';
  static String modelsCacheKey(String id) => '$modelsCacheKeyPrefix$id';
  static String modelCapabilitiesCacheKey(String id) =>
      '$modelCapabilitiesCacheKeyPrefix$id';

  // --- Registry ---

  bool get hasProviders => store.contains(providersKey);

  List<AiProviderMeta> get providers {
    final raw = store.read(providersKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      return AiProviderMeta.decodeList(raw);
    } catch (e) {
      onDecodeError?.call(e, providersKey);
      return const [];
    }
  }

  set providers(List<AiProviderMeta> value) {
    store.write(providersKey, AiProviderMeta.encodeList(value));
  }

  /// Seed the registry with [builtIns], preserving user toggles.
  ///
  /// Built-ins keep a stable leading order and have their display fields
  /// refreshed; custom providers keep their own order and are never touched.
  ///
  /// Returns whether anything was written, so a host app can avoid emitting a
  /// spurious change notification on every start.
  bool ensureInitialized({required List<AiProviderMeta> builtIns}) {
    final existing = providers;
    if (existing.isEmpty) {
      providers = builtIns;
      return true;
    }

    final byId = <String, AiProviderMeta>{for (final p in existing) p.id: p};
    final merged = <AiProviderMeta>[];

    for (final builtIn in builtIns) {
      final current = byId.remove(builtIn.id);
      if (current == null) {
        merged.add(builtIn);
        continue;
      }
      merged.add(
        current.copyWith(
          name: builtIn.name,
          type: builtIn.type,
          isBuiltIn: true,
          logoKey: builtIn.logoKey,
        ),
      );
    }

    for (final provider in existing) {
      if (byId.containsKey(provider.id)) {
        merged.add(provider);
      }
    }

    if (AiProviderMeta.encodeList(merged) ==
        AiProviderMeta.encodeList(existing)) {
      return false;
    }
    providers = merged;
    return true;
  }

  AiProviderMeta? providerById(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  void upsertProvider(AiProviderMeta meta) {
    final existing = List<AiProviderMeta>.from(providers);
    final index = existing.indexWhere((p) => p.id == meta.id);
    if (index >= 0) {
      existing[index] = meta;
    } else {
      existing.add(meta);
    }
    providers = existing;
  }

  void deleteProvider(String id) {
    final existing = providers;
    if (existing.isEmpty) return;
    providers = existing.where((p) => p.id != id).toList(growable: false);
  }

  // --- Per-provider configuration ---

  Map<String, String> configOf(String identifier) {
    final raw = store.read(configKey(identifier));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (e) {
      onDecodeError?.call(e, configKey(identifier));
      return {};
    }
  }

  void saveConfig(String identifier, Map<String, String> config) {
    store.write(configKey(identifier), jsonEncode(config));
  }

  /// Remove a provider's configuration and its caches.
  void deleteConfig(String identifier) {
    store.remove(configKey(identifier));
    store.remove(modelsCacheKey(identifier));
    store.remove(modelCapabilitiesCacheKey(identifier));
  }

  bool hasConfig(String identifier) => store.contains(configKey(identifier));

  // --- Default provider ---

  String get defaultProviderId =>
      store.read(defaultProviderKey) ?? _fallbackProviderId;

  set defaultProviderId(String id) => store.write(defaultProviderKey, id);

  static const String _fallbackProviderId = 'openai';

  // --- Model caches ---

  AiModelsCacheEntry? modelsCache(String providerId) {
    final key = modelsCacheKey(providerId);
    final raw = store.read(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final modelsRaw = decoded['models'];
      if (modelsRaw is! List) return null;
      final models = modelsRaw
          .map((e) => e?.toString())
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
      return (updatedAt: _updatedAtOf(decoded), models: models);
    } catch (e) {
      onDecodeError?.call(e, key);
      return null;
    }
  }

  void saveModelsCache(String providerId, List<String> models) {
    final sanitized = models
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    store.write(
      modelsCacheKey(providerId),
      jsonEncode({
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'models': sanitized,
      }),
    );
  }

  void clearModelsCache(String providerId) =>
      store.remove(modelsCacheKey(providerId));

  AiModelCapabilitiesCacheEntry? modelCapabilitiesCache(String providerId) {
    final key = modelCapabilitiesCacheKey(providerId);
    final raw = store.read(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final modelsRaw = decoded['models'];
      if (modelsRaw is! List) return null;
      final models = modelsRaw
          .whereType<Map>()
          .map(
            (e) => AiModelCapability.fromJson(
              e.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((e) => e.id.isNotEmpty)
          .toList(growable: false);
      return (updatedAt: _updatedAtOf(decoded), models: models);
    } catch (e) {
      onDecodeError?.call(e, key);
      return null;
    }
  }

  void saveModelCapabilitiesCache(
    String providerId,
    List<AiModelCapability> models,
  ) {
    final sanitized = <String, AiModelCapability>{
      for (final model in models)
        if (model.id.trim().isNotEmpty) model.id.trim(): model,
    }.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));

    store.write(
      modelCapabilitiesCacheKey(providerId),
      jsonEncode({
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'models': sanitized.map((e) => e.toJson()).toList(growable: false),
      }),
    );
  }

  void clearModelCapabilitiesCache(String providerId) =>
      store.remove(modelCapabilitiesCacheKey(providerId));

  /// A cache written by an older build may lack a usable timestamp; treat it as
  /// just-written rather than infinitely stale, matching prior behaviour.
  int _updatedAtOf(Map<dynamic, dynamic> decoded) {
    final value = decoded['updatedAt'];
    return value is int ? value : DateTime.now().millisecondsSinceEpoch;
  }

  // --- Per-feature routing ---

  /// Which provider a feature should actually use.
  ///
  /// Order: the feature's own choice, then the default chat provider, then the
  /// first provider that qualifies. [accept] adds a capability filter on top of
  /// "is enabled" — embeddings, for example, only work on OpenAI-compatible
  /// endpoints, so that feature passes a predicate and never silently lands on
  /// an Anthropic provider.
  ///
  /// The final fallback returns a possibly-disabled id rather than an empty
  /// string, so a corrupt or empty registry still yields something the caller
  /// can report on.
  String resolveEffectiveProviderId({
    String? preferredId,
    bool Function(AiProviderMeta meta)? accept,
  }) {
    bool qualifies(String id) {
      if (id.isEmpty) return false;
      final meta = providerById(id);
      if (meta == null || !meta.enabled) return false;
      return accept == null || accept(meta);
    }

    final preferred = (preferredId ?? '').trim();
    if (qualifies(preferred)) return preferred;

    final fallback = defaultProviderId.trim();
    if (qualifies(fallback)) return fallback;

    for (final provider in providers) {
      if (provider.enabled && (accept == null || accept(provider))) {
        return provider.id;
      }
    }

    return fallback.isNotEmpty ? fallback : preferred;
  }

  /// Providers that can serve embeddings and reranking.
  static bool acceptsOpenAiCompatible(AiProviderMeta meta) =>
      meta.type == AiProviderType.openaiCompatible ||
      meta.type == AiProviderType.openaiResponses;
}
