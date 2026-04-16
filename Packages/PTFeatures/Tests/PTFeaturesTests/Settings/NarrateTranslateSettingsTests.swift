import Foundation
import Testing
@testable import PTFeatures

@Suite("NarrateTranslateSettings")
struct NarrateTranslateSettingsTests {
    @Test("default target language persists")
    func defaultTargetLanguagePersists() {
        let suite = "test.narr.trans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs1 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs1.targetLanguage == "zh-Hans")

        NarrateTranslatePreferences.persistTargetLanguage("ja", defaults: defaults)
        let prefs2 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs2.targetLanguage == "ja")

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("use chat model toggle disables model picker")
    func useChatModelToggleDisablesModelPicker() {
        let suite = "test.narr.trans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs1 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs1.translationUseChatModel == true)

        NarrateTranslatePreferences.persistTranslationUseChatModel(false, defaults: defaults)
        let prefs2 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs2.translationUseChatModel == false)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("speed defaults to 1x")
    func speedDefaultsTo1x() {
        let suite = "test.narr.trans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs.narrationSpeed == 1.0)

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("narration backend persists")
    func narrationBackendPersists() {
        let suite = "test.narr.trans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs1 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs1.narrationBackend == "system")

        NarrateTranslatePreferences.persistNarrationBackend("openai", defaults: defaults)
        let prefs2 = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs2.narrationBackend == "openai")

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("narration speed persists")
    func narrationSpeedPersists() {
        let suite = "test.narr.trans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        NarrateTranslatePreferences.persistNarrationSpeed(1.5, defaults: defaults)
        let prefs = NarrateTranslatePreferences.load(defaults: defaults)
        #expect(prefs.narrationSpeed == 1.5)

        defaults.removePersistentDomain(forName: suite)
    }
}
