import '../models/ai_provider_meta.dart';
import 'ai_provider_center.dart';

/// Result of importing a portfolio.
class AiProviderImportResult {
  const AiProviderImportResult({
    required this.imported,
    required this.skipped,
    required this.secretsIncluded,
  });

  /// Provider ids that were written.
  final List<String> imported;

  /// Provider ids present in the payload but left alone.
  final List<String> skipped;

  /// Whether the payload carried API keys.
  final bool secretsIncluded;
}

/// Moves a whole provider setup between devices or projects.
///
/// Secrets are opt-in on export and never overwrite a local key with nothing:
/// importing a secret-free portfolio onto a configured device keeps the keys
/// already there.
abstract final class AiProviderPortfolio {
  static const int schemaVersion = 1;

  static Map<String, dynamic> export(
    AiProviderCenter center, {
    bool includeSecrets = false,
  }) {
    final providers = center.providers;
    final configs = <String, dynamic>{};

    for (final provider in providers) {
      final stored = center.configOf(provider.id);
      if (stored.isEmpty) continue;
      configs[provider.id] =
          includeSecrets ? stored : AiProviderCenter.safeConfig(stored);
    }

    return {
      'schemaVersion': schemaVersion,
      'containsSecrets': includeSecrets,
      'defaultProviderId': center.defaultProviderId,
      'providers': providers.map((p) => p.toJson()).toList(growable: false),
      'configs': configs,
    };
  }

  /// Apply [payload] to [center].
  ///
  /// Returns null when the payload is not a portfolio this version understands.
  static AiProviderImportResult? import(
    AiProviderCenter center,
    Map<String, dynamic> payload, {
    bool overwriteExisting = true,
    bool applyDefaultProvider = true,
  }) {
    final version = (payload['schemaVersion'] as num?)?.toInt();
    if (version == null || version > schemaVersion) return null;

    final rawProviders = payload['providers'];
    if (rawProviders is! List) return null;

    final rawConfigs = payload['configs'];
    final configs = rawConfigs is Map ? rawConfigs : const {};

    final imported = <String>[];
    final skipped = <String>[];

    for (final entry in rawProviders) {
      if (entry is! Map) continue;
      final meta = AiProviderMeta.fromJson(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (meta.id.isEmpty) continue;

      final existing = center.providerById(meta.id);
      if (existing != null && !overwriteExisting) {
        skipped.add(meta.id);
        continue;
      }

      center.upsertProvider(meta);

      final incoming = configs[meta.id];
      if (incoming is Map) {
        final next = <String, String>{
          for (final e in incoming.entries) '${e.key}': '${e.value}',
        };
        // A secret-free portfolio must not wipe keys already on this device.
        final local = center.configOf(meta.id);
        for (final secretKey in AiProviderCenter.secretConfigKeys) {
          final localSecret = local[secretKey];
          final hasIncoming = (next[secretKey] ?? '').trim().isNotEmpty;
          if (!hasIncoming && localSecret != null && localSecret.isNotEmpty) {
            next[secretKey] = localSecret;
          }
        }
        center.saveConfig(meta.id, next);
      }

      imported.add(meta.id);
    }

    if (applyDefaultProvider) {
      final defaultId = payload['defaultProviderId'];
      if (defaultId is String && defaultId.trim().isNotEmpty) {
        center.defaultProviderId = defaultId.trim();
      }
    }

    return AiProviderImportResult(
      imported: imported,
      skipped: skipped,
      secretsIncluded: payload['containsSecrets'] == true,
    );
  }
}
