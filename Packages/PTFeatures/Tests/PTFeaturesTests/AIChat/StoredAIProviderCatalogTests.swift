import Foundation
import Testing
import PTCore
@testable import PTAIServices
@testable import PTFeatures

@Suite("StoredAIProviderCatalog")
struct StoredAIProviderCatalogTests {
    private func makeDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "stored-ai-provider-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    @Test("snapshot honors the persisted preferred provider and model")
    func snapshotHonorsPreferredProviderAndModel() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gemini-1.5-pro", forKey: AppConfig.Keys.aiModelID)

        let snapshot = StoredAIProviderCatalog(defaults: defaults).snapshot(
            toolRegistry: .default,
            toolContext: ToolContext()
        )

        #expect(snapshot.selection.providerId == "gemini")
        #expect(snapshot.selection.modelId == "gemini-1.5-pro")
        #expect(snapshot.runtime.providers.contains { $0.id == "gemini" })
    }

    @Test("snapshot includes configured custom providers with their saved model")
    func snapshotIncludesConfiguredCustomProvider() throws {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = CustomProviderEntry(
            id: "custom_demo",
            displayName: "Demo Gateway",
            baseURL: "https://example.com"
        )
        CustomProviderStore.save([entry], defaults: defaults)
        defaults.set("https://example.com", forKey: "ai_base_url_custom_demo")
        defaults.set("demo-model", forKey: "ai_model_for_custom_demo")
        defaults.set("custom_demo", forKey: AppConfig.Keys.aiProviderID)

        let snapshot = StoredAIProviderCatalog(defaults: defaults).snapshot(
            toolRegistry: .default,
            toolContext: ToolContext()
        )

        let provider = try #require(snapshot.runtime.providers.first(where: { $0.id == "custom_demo" }))
        #expect(provider.displayName == "Demo Gateway")
        #expect(provider.models.first?.id == "demo-model")
        #expect(snapshot.selection.providerId == "custom_demo")
        #expect(snapshot.selection.modelId == "demo-model")
    }

    @Test("snapshot falls back to an available provider when the preferred one is unavailable")
    func snapshotFallsBackToAvailableProvider() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("missing-provider", forKey: AppConfig.Keys.aiProviderID)

        let snapshot = StoredAIProviderCatalog(defaults: defaults).snapshot(
            toolRegistry: .default,
            toolContext: ToolContext()
        )

        #expect(snapshot.runtime.providers.isEmpty == false)
        #expect(snapshot.selection.providerId == snapshot.runtime.providers.first?.id)
        #expect(snapshot.selection.modelId == snapshot.runtime.providers.first?.models.first?.id)
    }

    @Test("snapshot does not leak the global model id into other providers")
    func snapshotDoesNotLeakGlobalModelIntoOtherProviders() throws {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("anthropic", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("claude-sonnet-4-20250514", forKey: AppConfig.Keys.aiModelID)

        let snapshot = StoredAIProviderCatalog(defaults: defaults).snapshot(
            toolRegistry: .default,
            toolContext: ToolContext()
        )

        let openAIProvider = try #require(snapshot.runtime.providers.first(where: { $0.id == "openai" }))
        #expect(openAIProvider.models.first?.id != "claude-sonnet-4-20250514")
    }

    @Test("resolveCurrentProvider wires stored Gemini runtime config")
    func resolveCurrentProviderWiresStoredGeminiRuntimeConfig() throws {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gemini-2.5-flash", forKey: "ai_model_for_gemini")
        defaults.set(true, forKey: "ai_include_thoughts_gemini")
        defaults.set("strict", forKey: "ai_safety_gemini")

        let resolved = StoredAIProviderCatalog(defaults: defaults).resolveCurrentProvider()
        let provider = try #require(resolved.provider as? GeminiProvider)

        #expect(resolved.providerId == "gemini")
        #expect(resolved.modelId == "gemini-2.5-flash")
        #expect(provider.includeThoughts == true)
        #expect(provider.safetyPreset == .strict)
    }

    @Test("resolveCurrentProvider keeps Gemini thoughts disabled when unset")
    func resolveCurrentProviderLeavesGeminiThoughtsDisabledWhenUnset() throws {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gemini-2.5-flash", forKey: "ai_model_for_gemini")

        let resolved = StoredAIProviderCatalog(defaults: defaults).resolveCurrentProvider()
        let provider = try #require(resolved.provider as? GeminiProvider)

        #expect(resolved.providerId == "gemini")
        #expect(provider.includeThoughts == false)
    }

    @Test("snapshot marks persisted reasoning-capable models as supporting thinking")
    func snapshotMarksPersistedReasoningModelsAsThinkingCapable() throws {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openai", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gpt-5", forKey: "ai_model_for_openai")
        defaults.set("gemini-2.5-flash", forKey: "ai_model_for_gemini")

        let snapshot = StoredAIProviderCatalog(defaults: defaults).snapshot(
            toolRegistry: .default,
            toolContext: ToolContext()
        )

        let openAIProvider = try #require(snapshot.runtime.providers.first(where: { $0.id == "openai" }))
        let geminiProvider = try #require(snapshot.runtime.providers.first(where: { $0.id == "gemini" }))
        let openAIModel = try #require(openAIProvider.models.first(where: { $0.id == "gpt-5" }))
        let geminiModel = try #require(geminiProvider.models.first(where: { $0.id == "gemini-2.5-flash" }))

        #expect(openAIModel.supportsThinking)
        #expect(geminiModel.supportsThinking)
    }

    @Test("resolveCurrentProvider narrows capabilities to the selected model")
    func resolveCurrentProviderNarrowsCapabilitiesToSelectedModel() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openai", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gpt-4o", forKey: "ai_model_for_openai")

        let resolved = StoredAIProviderCatalog(defaults: defaults).resolveCurrentProvider()

        #expect(resolved.providerId == "openai")
        #expect(resolved.modelId == "gpt-4o")
        #expect(resolved.provider.supportedCapabilities.contains(.vision))
        #expect(resolved.provider.supportedCapabilities.contains(.thinking) == false)
    }
}
