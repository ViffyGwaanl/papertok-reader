import Foundation
import Testing
@testable import PTCore

@Suite("AppLocalization")
struct AppLocalizationTests {
    @Test("loads localized strings from an injected bundle and locale")
    func loadsLocalizedStrings() {
        let bundle = Bundle.module

        #expect(
            AppLocalization.string(
                "test.greeting",
                bundle: bundle,
                locale: Locale(identifier: "en")
            ) == "Hello"
        )
        #expect(
            AppLocalization.string(
                "test.greeting",
                bundle: bundle,
                locale: Locale(identifier: "zh-Hans")
            ) == "你好"
        )
    }

    @Test("formats localized strings with arguments")
    func formatsLocalizedStrings() {
        let formatted = AppLocalization.format(
            "test.items",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            3
        )

        #expect(formatted == "3 项")
    }

    @Test("formats localized strings with a fallback format when provided")
    func formatsLocalizedStringsWithFallback() {
        let localized = AppLocalization.format(
            "test.items",
            "%d items",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            2
        )
        let fallback = AppLocalization.format(
            "missing.items",
            "%d items",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            2
        )

        #expect(localized == "2 项")
        #expect(fallback == "2 items")
    }

    @Test("falls back to the key when no localization exists")
    func fallsBackToKey() {
        #expect(
            AppLocalization.string(
                "missing.key",
                bundle: Bundle.module,
                locale: Locale(identifier: "zh-Hans")
            ) == "missing.key"
        )
    }
}
