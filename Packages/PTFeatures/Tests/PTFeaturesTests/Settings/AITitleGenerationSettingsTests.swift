import Foundation
import Testing
@testable import PTFeatures

@Suite("AITitleGenerationSettings")
struct AITitleGenerationSettingsTests {
    @Test("enabled toggle persists round trip")
    func enabledTogglePersistsRoundTrip() {
        let suite = "test.ai.title.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs1 = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs1.isEnabled == true)

        AITitleGenerationPreferences.persistEnabled(false, defaults: defaults)
        let prefs2 = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs2.isEnabled == false)

        AITitleGenerationPreferences.persistEnabled(true, defaults: defaults)
        let prefs3 = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs3.isEnabled == true)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("max words defaults to 8")
    func maxWordsDefaultsTo8() {
        let suite = "test.ai.title.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs.maxWords == 8)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("max words persists round trip")
    func maxWordsPersistsRoundTrip() {
        let suite = "test.ai.title.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        AITitleGenerationPreferences.persistMaxWords(12, defaults: defaults)
        let prefs = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs.maxWords == 12)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("use chat model defaults to true")
    func useChatModelDefaultsToTrue() {
        let suite = "test.ai.title.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs = AITitleGenerationPreferences.load(defaults: defaults)
        #expect(prefs.useChatModel == true)

        defaults.removePersistentDomain(forName: suite)
    }
}
