import Foundation
import Testing
import PTCore
import PTAIServices
import PTFeatures
@testable import PaperTokReader

@Suite("User-facing localization mappings")
struct UserFacingLocalizationMappingTests {
    @Test("shortcut AI service errors use catalog-backed localized messages")
    func shortcutAIServiceErrorsUseCatalogMessages() {
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

    @Test("provider and organize errors use catalog-backed localized messages")
    func providerAndOrganizeErrorsUseCatalogMessages() {
        #expect(
            ProviderFactoryError.missingBaseURL(.azure).errorDescription
                == AppLocalization.format("errors.ai.provider_base_url_required_format", bundle: .main, locale: .autoupdatingCurrent, "azure")
        )
        #expect(
            ProviderFactoryError.missingDeploymentName.errorDescription
                == AppLocalization.string("errors.ai.missing_deployment_name", bundle: .main)
        )
        #expect(
            AIOrganizeService.OrganizeError.noBooks.errorDescription
                == AppLocalization.string("errors.organize.no_books", bundle: .main)
        )
        #expect(
            AIOrganizeService.OrganizeError.noProviderResponse.errorDescription
                == AppLocalization.string("errors.organize.empty_response", bundle: .main)
        )
        #expect(
            AIOrganizeService.OrganizeError.invalidResponse("bad json").errorDescription
                == AppLocalization.format("errors.organize.invalid_response_format", bundle: .main, locale: .autoupdatingCurrent, "bad json")
        )
    }

    @Test("sync-related errors use catalog-backed localized messages")
    func syncErrorsUseCatalogMessages() {
        #expect(
            AISettingsSyncError.encryptionFailed.errorDescription
                == AppLocalization.string("errors.sync.ai_settings_encryption_failed", bundle: .main)
        )
        #expect(
            AISettingsSyncError.decryptionFailed.errorDescription
                == AppLocalization.string("errors.sync.ai_settings_decryption_failed", bundle: .main)
        )
        #expect(
            AISettingsSyncError.invalidPassphrase.errorDescription
                == AppLocalization.string("errors.sync.ai_settings_invalid_passphrase", bundle: .main)
        )
        #expect(
            IncrementalSyncError.unknownEntity("notes").errorDescription
                == AppLocalization.format("errors.sync.unknown_entity_format", bundle: .main, locale: .autoupdatingCurrent, "notes")
        )
        #expect(
            IncrementalSyncError.conflictRequiresUserInput("books").errorDescription
                == AppLocalization.format("errors.sync.manual_conflict_required_format", bundle: .main, locale: .autoupdatingCurrent, "books")
        )
    }
}
