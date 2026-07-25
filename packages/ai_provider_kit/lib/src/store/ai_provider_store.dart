/// Key-value persistence used by [AiProviderCenter].
///
/// Reads are synchronous and writes are fire-and-forget, which matches
/// `SharedPreferences` (the usual Flutter choice) where values are held in
/// memory and flushed in the background. A host app backed by async storage
/// should keep an in-memory cache and implement this over it.
///
/// ## Secrets
///
/// API keys are the one thing here worth protecting. By default they are
/// stored through the same channel as everything else — for `SharedPreferences`
/// that means plain text inside the app container, guarded by the OS sandbox
/// and device encryption but not by the Keychain/Keystore.
///
/// Override the `*Secret` methods (and [hasSecureSecretChannel]) to route them
/// somewhere stronger. [AiProviderCenter] then keeps secrets out of the plain
/// config entry entirely; see `AiProviderCenter.migrateSecretsToSecureChannel`
/// for moving an existing install across.
abstract class AiProviderStore {
  const AiProviderStore();

  String? read(String key);
  void write(String key, String value);
  void remove(String key);
  bool contains(String key);

  /// Whether [readSecret]/[writeSecret] reach different storage than [read].
  ///
  /// While false, secrets stay inline in the provider config, which keeps the
  /// on-disk layout of an existing install unchanged.
  bool get hasSecureSecretChannel => false;

  String? readSecret(String key) => read(key);
  void writeSecret(String key, String value) => write(key, value);
  void removeSecret(String key) => remove(key);
}

/// In-memory store, for tests and for apps that do not persist provider config.
class MemoryAiProviderStore extends AiProviderStore {
  MemoryAiProviderStore([Map<String, String>? initial])
      : _values = {...?initial};

  final Map<String, String> _values;

  /// Current contents, for assertions and for exporting to another store.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);

  @override
  bool contains(String key) => _values.containsKey(key);
}

/// In-memory store with a separate secret compartment, for testing the secure
/// path without a platform keystore.
class MemorySecureAiProviderStore extends MemoryAiProviderStore {
  MemorySecureAiProviderStore([super.initial]);

  final Map<String, String> secrets = {};

  @override
  bool get hasSecureSecretChannel => true;

  @override
  String? readSecret(String key) => secrets[key];

  @override
  void writeSecret(String key, String value) => secrets[key] = value;

  @override
  void removeSecret(String key) => secrets.remove(key);
}
