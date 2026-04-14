import Foundation
import Testing
@testable import PTCore

@Suite("AppLocalization")
struct AppLocalizationTests {
    private enum LocalizedSampleError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Localized sample failure"
        }
    }

    private enum PlainSampleError: Error {
        case failed
    }

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

    @Test("formats localized strings with string arguments")
    func formatsLocalizedStringsWithStringArguments() {
        let formatted = AppLocalization.format(
            "test.detail",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            "自定义"
        )

        #expect(formatted == "详情：自定义")
    }

    @Test("formats localized strings with a fallback format when provided")
    func formatsLocalizedStringsWithFallback() {
        let localized = AppLocalization.format(
            "test.items",
            fallback: "%d items",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            2
        )
        let fallback = AppLocalization.format(
            "missing.items",
            fallback: "%d items",
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

    @Test("returns LocalizedError descriptions when available")
    func returnsLocalizedErrorDescription() {
        #expect(AppLocalization.localizedErrorDescription(LocalizedSampleError.failed) == "Localized sample failure")
        #expect(AppLocalization.localizedErrorDescription(PlainSampleError.failed) == nil)
    }

    @Test("prefers localized error descriptions before falling back to a localized message")
    func prefersLocalizedErrorDescriptions() {
        let localized = AppLocalization.userFacingErrorMessage(
            for: LocalizedSampleError.failed,
            fallbackKey: "test.greeting",
            fallback: "Fallback message",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans")
        )
        let fallback = AppLocalization.userFacingErrorMessage(
            for: PlainSampleError.failed,
            fallbackKey: "test.greeting",
            fallback: "Fallback message",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(localized == "Localized sample failure")
        #expect(fallback == "你好")
    }

    @Test("can prefer the catalog fallback as the primary user-facing message")
    func canPreferCatalogFallback() {
        let fallbackFirst = AppLocalization.userFacingErrorMessage(
            for: LocalizedSampleError.failed,
            fallbackKey: "test.greeting",
            fallback: "Fallback message",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans"),
            priority: .preferFallback
        )

        #expect(fallbackFirst == "你好")
    }

    @Test("can use a catalog key without an English fallback literal")
    func supportsKeyOnlyUserFacingFallback() {
        let fallback = AppLocalization.userFacingErrorMessage(
            for: PlainSampleError.failed,
            fallbackKey: "test.greeting",
            bundle: Bundle.module,
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(fallback == "你好")
    }
}
