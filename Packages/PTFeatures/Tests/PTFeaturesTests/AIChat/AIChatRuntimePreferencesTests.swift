import Foundation
import Testing
import PTCore
@testable import PTAIServices
@testable import PTFeatures

@Suite("AIChatRuntimePreferences")
struct AIChatRuntimePreferencesTests {
    private func makeDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "ai-chat-runtime-prefs-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    private func roundTrip(_ settings: AIChatViewModel.ChatGenerationSettings, providerId: String) -> AIChatViewModel.ChatGenerationSettings {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AIChatRuntimePreferences.persist(settings, defaults: defaults, providerId: providerId)
        return AIChatRuntimePreferences
            .load(defaults: defaults, providerId: providerId)
            .generationSettings
    }

    // MARK: - A. Penalty round-trip

    @Test("presence penalty round trips through user defaults")
    func presencePenaltyRoundTripsThroughUserDefaults() {
        var settings = AIChatViewModel.ChatGenerationSettings.default
        settings.presencePenalty = 0.5
        let loaded = roundTrip(settings, providerId: "openai")
        #expect(loaded.presencePenalty == 0.5)
    }

    @Test("frequency penalty round trips through user defaults")
    func frequencyPenaltyRoundTripsThroughUserDefaults() {
        var settings = AIChatViewModel.ChatGenerationSettings.default
        settings.frequencyPenalty = -1.25
        let loaded = roundTrip(settings, providerId: "openai")
        #expect(loaded.frequencyPenalty == -1.25)
    }

    @Test("penalties default to zero when unset")
    func penaltiesDefaultToZeroWhenUnset() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loaded = AIChatRuntimePreferences.load(defaults: defaults, providerId: "openai")
        #expect(loaded.generationSettings.presencePenalty == 0.0)
        #expect(loaded.generationSettings.frequencyPenalty == 0.0)
    }

    // MARK: - B. Stop sequences parsing

    @Test("parseStopSequences handles a single token")
    func parseStopSequencesHandlesSingleToken() {
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("END") == ["END"])
    }

    @Test("parseStopSequences handles multiple comma-separated tokens")
    func parseStopSequencesHandlesMultipleTokens() {
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("END,STOP,QUIT") == ["END", "STOP", "QUIT"])
    }

    @Test("parseStopSequences trims whitespace around tokens")
    func parseStopSequencesTrimsWhitespace() {
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("  END  , STOP ") == ["END", "STOP"])
    }

    @Test("parseStopSequences ignores empty tokens")
    func parseStopSequencesIgnoresEmptyTokens() {
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("END,,STOP,") == ["END", "STOP"])
    }

    @Test("parseStopSequences handles empty input")
    func parseStopSequencesHandlesEmptyInput() {
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("") == [])
        #expect(AIChatRuntimePreferences.parseStopSequencesInput("   ") == [])
    }

    @Test("stop sequences round trip through persistence")
    func stopSequencesRoundTrip() {
        var settings = AIChatViewModel.ChatGenerationSettings.default
        settings.stopSequences = ["END", "DONE"]
        let loaded = roundTrip(settings, providerId: "openai")
        #expect(loaded.stopSequences == ["END", "DONE"])
    }

    // MARK: - C. Thinking budget round-trip

    @Test("thinking budget round trips through user defaults")
    func thinkingBudgetRoundTripsThroughUserDefaults() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AIChatRuntimePreferences.persistThinkingBudget(8192, defaults: defaults, providerId: "anthropic")
        let loaded = AIChatRuntimePreferences.loadThinkingBudget(defaults: defaults, providerId: "anthropic")
        #expect(loaded == 8192)
        let prefs = AIChatRuntimePreferences.load(defaults: defaults, providerId: "anthropic")
        #expect(prefs.generationSettings.thinkingBudgetTokens == 8192)
    }

    @Test("thinking budget defaults to nil when unset")
    func thinkingBudgetDefaultsToNilWhenUnset() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loaded = AIChatRuntimePreferences.loadThinkingBudget(defaults: defaults, providerId: "anthropic")
        #expect(loaded == nil)
        let prefs = AIChatRuntimePreferences.load(defaults: defaults, providerId: "anthropic")
        #expect(prefs.generationSettings.thinkingBudgetTokens == nil)
    }

    @Test("thinking budget cleared when persisted as nil")
    func thinkingBudgetClearedWhenPersistedAsNil() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AIChatRuntimePreferences.persistThinkingBudget(4096, defaults: defaults, providerId: "gemini")
        AIChatRuntimePreferences.persistThinkingBudget(nil, defaults: defaults, providerId: "gemini")
        #expect(AIChatRuntimePreferences.loadThinkingBudget(defaults: defaults, providerId: "gemini") == nil)
    }
}
