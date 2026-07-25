# ai_provider_kit

Provider management for Dart/Flutter AI apps: **which provider, which model, which key, which endpoint**.

It stops there on purpose. Talking to the model — chat, streaming, tool calling — is left to whatever
client you prefer (`langchain_dart`, `openai_dart`, or plain `http`). That boundary is what makes this
reusable: swapping client stacks doesn't touch provider handling, and adding a provider doesn't touch
your chat code.

No Flutter, no Riverpod, no `shared_preferences`, no LangChain. The only dependency is `dio`.

## What you get

| | |
| --- | --- |
| **Registry** | Built-in + custom providers, enable/disable, stable ids |
| **Catalog** | 18 presets (OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Groq, xAI, Mistral, Together, Fireworks, DashScope, SiliconFlow, Moonshot, Zhipu, Volcengine Ark, Ollama, LM Studio…) each with the URL to get an API key |
| **Keys** | Multiple keys per provider, round-robin rotation, cooldown, per-key test history |
| **Models** | Fetch the live model list and capabilities (OpenAI-compatible / Anthropic / Gemini), cached |
| **Routing** | Per-feature model selection — chat, translation, embeddings… each can use a different provider, with a capability filter |
| **Diagnostics** | Connectivity test returning latency and a *classified* error, not a raw exception string |
| **Portability** | Export/import a whole setup as JSON, secrets opt-in |

## Install

```yaml
dependencies:
  ai_provider_kit:
    path: packages/ai_provider_kit
```

## Five-minute integration

**1. Implement storage.** Reads are synchronous, writes are fire-and-forget — this matches
`SharedPreferences`. Back it with anything you like.

```dart
class PrefsStore extends AiProviderStore {
  PrefsStore(this.prefs);
  final SharedPreferences prefs;

  @override String? read(String key) => prefs.getString(key);
  @override void write(String key, String value) => prefs.setString(key, value);
  @override void remove(String key) => prefs.remove(key);
  @override bool contains(String key) => prefs.containsKey(key);
}
```

**2. Seed the registry** with the presets you want to offer:

```dart
final center = AiProviderCenter(PrefsStore(prefs));
final now = DateTime.now().millisecondsSinceEpoch;

center.ensureInitialized(
  builtIns: [
    AiProviderPresets.openai,
    AiProviderPresets.claude,
    AiProviderPresets.deepseek,
  ].map((p) => p.toMeta(now: now)).toList(),
);
```

Built-ins keep a stable order and get their display fields refreshed on every call, while the user's
enable/disable choices and any custom providers survive untouched.

**3. Save a key and verify it actually works:**

```dart
center.saveConfig('openai', {
  'url': AiProviderPresets.openai.defaultUrl,
  'api_key': 'sk-...',
  'model': 'gpt-4o-mini',
});

final result = await AiProviderTester.test(
  provider: center.providerById('openai')!,
  config: center.configOf('openai'),
);

if (!result.ok) {
  // Map result.failure to your own copy: `unauthorized` means replace the key,
  // `notFound` means fix the URL. Don't show the raw message to users.
}
```

**4. Resolve a provider and hand off to your client:**

```dart
final providerId = center.resolveEffectiveProviderId(
  preferredId: myTranslationProviderId,
);
final config = AiEndpointConfig.fromRawConfig(
  registryIdentifierForAiProvider(center.providerById(providerId)),
  center.configOf(providerId),
);

// config.baseUrl / apiKey / model / headers / temperature … now feed your client.
```

`AiEndpointConfig` normalizes the messy parts: it strips `/chat/completions`-style suffixes so a URL
pasted from provider docs still works as a base, parses headers from either JSON or `k=v;k=v`, and
merges a per-feature override on top of a provider's own settings.

## Per-feature routing

Different features want different models — a cheap model for chat titles, an embedding-capable
endpoint for search. `resolveEffectiveProviderId` picks: the feature's own choice, then the default
provider, then the first that qualifies.

`accept` adds a capability filter, which matters more than it looks: embeddings only work on
OpenAI-style endpoints, so without a filter a feature can silently land on an Anthropic provider and
fail at request time.

```dart
center.resolveEffectiveProviderId(
  preferredId: myEmbeddingProviderId,
  accept: AiProviderCenter.acceptsOpenAiCompatible,
);
```

## Moving a setup between devices or projects

```dart
final payload = AiProviderPortfolio.export(center);                     // no secrets
final payload = AiProviderPortfolio.export(center, includeSecrets: true);
AiProviderPortfolio.import(otherCenter, payload);
```

Importing a secret-free portfolio onto a configured device keeps the keys already there rather than
blanking them.

## Storage keys

Stable and documented, so you can migrate into or out of this package by hand:

| Key | Holds |
| --- | --- |
| `aiProvidersV1` | Provider registry (JSON list) |
| `aiConfig_<id>` | One provider's config, including secrets |
| `selectedAiService` | Default provider id |
| `aiModelsCacheV1_<id>` | Cached model ids |
| `aiModelCapabilitiesCacheV1_<id>` | Cached model capabilities |

## Secrets

`api_key` and `api_keys` (`AiProviderCenter.secretConfigKeys`) are the only values worth protecting.

By default they sit inside the `aiConfig_<id>` blob alongside everything else. Backed by
`SharedPreferences` that means plain text in the app container — guarded by the OS sandbox and device
encryption, but not by the Keychain/Keystore.

**To store them properly, give the store a secret channel:**

```dart
class SecureStore extends PrefsStore {
  SecureStore(super.prefs, this.secure);
  final MySecureStorage secure;   // Keychain / Keystore / libsecret / DPAPI

  @override bool get hasSecureSecretChannel => true;
  @override String? readSecret(String key) => secure.read(key);
  @override void writeSecret(String key, String value) => secure.write(key, value);
  @override void removeSecret(String key) => secure.delete(key);
}
```

`AiProviderCenter` then keeps secrets out of the plain entry entirely, writing them to
`aiSecretV1_<id>` through the secret channel while `configOf` still returns one merged map — callers
don't change.

For an install that already has plaintext keys, call this once at startup:

```dart
center.migrateSecretsToSecureChannel();
```

It is idempotent, and it drops a plaintext copy **only after reading the secret back out of secure
storage successfully** — a keystore that silently fails loses nothing. Without a secret channel it
returns an empty list and changes nothing, so calling it unconditionally is safe.

Independently of storage: strip secrets with `AiProviderCenter.safeConfig` before syncing or backing
up. The package deliberately does not decide that for you, because only the host app knows what
leaves the device.

## Testing

`MemoryAiProviderStore` makes the whole thing testable without any platform bindings:

```dart
final center = AiProviderCenter(MemoryAiProviderStore());
```

```bash
cd packages/ai_provider_kit && dart test
```

## A note on dio versions

`classifyDioException` deliberately uses a `default` branch instead of an exhaustive enum match: dio
adds `DioExceptionType` values across 5.x releases, and a host app may pin an older version than this
package resolves to standalone.
