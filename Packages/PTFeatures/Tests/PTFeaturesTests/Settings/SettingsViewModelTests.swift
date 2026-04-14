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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
