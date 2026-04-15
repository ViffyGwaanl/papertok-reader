import Foundation
import Testing
@testable import PTFeatures

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    @Test("defaults use locale-aware Chinese font family when unset")
    func defaultsUseChineseFontFamily() {
        let defaults = makeDefaults()
        let viewModel = SettingsViewModel(
            defaults: defaults,
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(viewModel.defaultFontFamily == "Songti SC")
    }

    @Test("defaults use non-Chinese fallback font family when unset")
    func defaultsUseNonChineseFallbackFontFamily() {
        let defaults = makeDefaults()
        let viewModel = SettingsViewModel(
            defaults: defaults,
            locale: Locale(identifier: "en")
        )

        #expect(viewModel.defaultFontFamily == "Arial")
    }

    @Test("resetReadingDetail restores locale-aware font defaults")
    func resetReadingDetailRestoresLocaleAwareFontDefaults() {
        let defaults = makeDefaults()
        let viewModel = SettingsViewModel(
            defaults: defaults,
            locale: Locale(identifier: "zh-Hans")
        )

        viewModel.defaultFontSize = 28
        viewModel.defaultFontFamily = "Helvetica Neue"
        viewModel.lineHeight = 1.9

        viewModel.resetReadingDetail()

        #expect(viewModel.defaultFontSize == AppConfig.Defaults.defaultFontSize)
        #expect(viewModel.defaultFontFamily == BookStyle.preferredDefaultFontFamily(locale: .autoupdatingCurrent))
        #expect(viewModel.lineHeight == 1.4)
    }

    @Test("save persists the selected model under the active provider key as well")
    func savePersistsProviderScopedModelSelection() {
        let defaults = makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)

        viewModel.aiProviderID = "anthropic"
        viewModel.aiModelID = "claude-opus-4-20250514"

        viewModel.save()

        #expect(defaults.string(forKey: AppConfig.Keys.aiProviderID) == "anthropic")
        #expect(defaults.string(forKey: AppConfig.Keys.aiModelID) == "claude-opus-4-20250514")
        #expect(defaults.string(forKey: "ai_model_for_anthropic") == "claude-opus-4-20250514")
    }

    @Test("init prefers the provider-scoped model for the active provider")
    func initPrefersProviderScopedModelForActiveProvider() {
        let defaults = makeDefaults()
        defaults.set("openai", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gpt-4.1", forKey: AppConfig.Keys.aiModelID)
        defaults.set("gpt-4o", forKey: "ai_model_for_openai")

        let viewModel = SettingsViewModel(defaults: defaults)

        #expect(viewModel.aiProviderID == "openai")
        #expect(viewModel.aiModelID == "gpt-4o")
    }

    @Test("switching providers restores that provider's persisted model")
    func switchingProvidersRestoresPersistedModel() {
        let defaults = makeDefaults()
        defaults.set("openai", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gpt-4o", forKey: "ai_model_for_openai")
        defaults.set("claude-sonnet-4-20250514", forKey: "ai_model_for_anthropic")

        let viewModel = SettingsViewModel(defaults: defaults)
        viewModel.aiProviderID = "anthropic"

        #expect(viewModel.aiModelID == "claude-sonnet-4-20250514")
    }

    @Test("switching providers falls back to the provider default model")
    func switchingProvidersFallsBackToDefaultModel() {
        let defaults = makeDefaults()
        defaults.set("openai", forKey: AppConfig.Keys.aiProviderID)
        defaults.set("gpt-4o", forKey: "ai_model_for_openai")

        let viewModel = SettingsViewModel(defaults: defaults)
        viewModel.aiProviderID = "gemini"

        #expect(viewModel.aiModelID == AIProviderID.gemini.defaultModel)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
