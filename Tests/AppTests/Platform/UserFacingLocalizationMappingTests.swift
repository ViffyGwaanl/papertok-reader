import Foundation
import Testing
import PTCore
@testable import PaperTokReader

@Suite("User-facing localization mappings")
struct UserFacingLocalizationMappingTests {
    @Test("shortcut AI service errors use catalog-backed localized messages")
    func shortcutAIServiceErrorsUseCatalogMessages() {
        #expect(
            ShortcutAIServiceError.unsupportedProvider("custom").errorDescription
                == AppLocalization.format("errors.ai.shortcut_unsupported_provider_format", bundle: .main, locale: .autoupdatingCurrent, "custom")
        )
        #expect(
            ShortcutAIServiceError.emptyResponse.errorDescription
                == AppLocalization.string("errors.ai.shortcut_empty_response", bundle: .main)
        )
        #expect(
            ShortcutAIServiceError.invalidImageData.errorDescription
                == AppLocalization.string("errors.ai.shortcut_invalid_image", bundle: .main)
        )
    }

    @Test("reader locator resolver errors use catalog-backed localized messages")
    func readerLocatorResolverErrorsUseCatalogMessages() {
        #expect(
            ReaderLocatorResolver.ResolveError.missingBookId.errorDescription
                == AppLocalization.string("errors.deeplink.missing_book_id", bundle: .main)
        )
        #expect(
            ReaderLocatorResolver.ResolveError.invalidBookId("abc").errorDescription
                == AppLocalization.format("errors.deeplink.invalid_book_id_format", bundle: .main, locale: .autoupdatingCurrent, "abc")
        )
        #expect(
            ReaderLocatorResolver.ResolveError.bookNotFound(42).errorDescription
                == AppLocalization.format("errors.deeplink.book_not_found_format", bundle: .main, locale: .autoupdatingCurrent, Int64(42))
        )
        #expect(
            ReaderLocatorResolver.ResolveError.invalidLocator("page:NaN").errorDescription
                == AppLocalization.format("errors.deeplink.invalid_locator_format", bundle: .main, locale: .autoupdatingCurrent, "page:NaN")
        )
    }
}
