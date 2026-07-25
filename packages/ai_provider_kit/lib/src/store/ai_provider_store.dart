/// Key-value persistence used by [AiProviderCenter].
///
/// Reads are synchronous and writes are fire-and-forget, which matches
/// `SharedPreferences` (the usual Flutter choice) where values are held in
/// memory and flushed in the background. A host app backed by async storage
/// should keep an in-memory cache and implement this over it.
abstract class AiProviderStore {
  const AiProviderStore();

  String? read(String key);
  void write(String key, String value);
  void remove(String key);
  bool contains(String key);
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
