import Testing
@testable import PTFeatures

@Suite("ReaderStateScreen")
struct ReaderStateScreenTests {
    @Test("loading state renders loading title as body")
    func loadingStateRendersSpinnerAndTitle() {
        let body = ReaderStateScreen.bodyText(for: .loading(progress: nil))
        #expect(body.isEmpty == false)
        #expect(ReaderStateScreen.iconName(for: .loading(progress: nil)) == "hourglass")
    }

    @Test("empty state renders icon, title and body")
    func emptyStateRendersIconTitleBody() {
        let state = ReaderState.empty(reason: .noPages)
        #expect(ReaderStateScreen.iconName(for: state) == "book.closed")
        #expect(ReaderStateScreen.titleText(for: state).isEmpty == false)
        #expect(ReaderStateScreen.bodyText(for: state).isEmpty == false)
    }

    @Test("empty unsupported format renders questionmark icon")
    func emptyUnsupportedFormatRenders() {
        let state = ReaderState.empty(reason: .unsupportedFormat("mobi"))
        let body = ReaderStateScreen.bodyText(for: state)
        #expect(body.isEmpty == false)
        #expect(ReaderStateScreen.iconName(for: state) == "doc.questionmark")
    }

    @Test("failed recoverable state shows retry button")
    func failedStateRendersRetryButtonWhenRecoverable() {
        let err = ReaderRenderError(kind: .openFailed, underlyingMessage: "boom", isRecoverable: true)
        #expect(ReaderStateScreen.showsRetryButton(for: .failed(error: err)))
    }

    @Test("failed non-recoverable state hides retry button")
    func failedStateHidesRetryButtonWhenNotRecoverable() {
        let err = ReaderRenderError(kind: .parsingFailed, underlyingMessage: nil, isRecoverable: false)
        #expect(ReaderStateScreen.showsRetryButton(for: .failed(error: err)) == false)
    }

    @Test("permission denied state renders lock icon")
    func permissionDeniedStateRendersLockIcon() {
        let state = ReaderState.permissionDenied(detail: "iCloud")
        #expect(ReaderStateScreen.iconName(for: state) == "lock.shield")
        #expect(ReaderStateScreen.bodyText(for: state).contains("iCloud"))
    }

    @Test("ready state returns empty title and body")
    func readyStateRendersEmptyView() {
        #expect(ReaderStateScreen.titleText(for: .ready).isEmpty)
        #expect(ReaderStateScreen.bodyText(for: .ready).isEmpty)
        #expect(ReaderState.ready.shouldPresentStateScreen == false)
    }

    @Test("failed state truncates underlying message past 200 characters")
    func failedStateTruncatesLongMessage() {
        let long = String(repeating: "A", count: 400)
        let err = ReaderRenderError(kind: .unknown, underlyingMessage: long, isRecoverable: true)
        let body = ReaderStateScreen.bodyText(for: .failed(error: err))
        #expect(body.contains("…"))
        #expect(body.count < 400)
    }

    @Test("all error kinds have distinct localization keys")
    func errorKindLocalizationKeysDistinct() {
        let kinds: [ReaderRenderError.Kind] = [.openFailed, .parsingFailed, .missingResource, .fileSystemError, .unknown]
        let keys = Set(kinds.map { $0.localizationKey })
        #expect(keys.count == kinds.count)
    }
}
