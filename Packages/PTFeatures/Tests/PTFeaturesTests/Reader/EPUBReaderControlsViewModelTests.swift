import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("EPUBReaderControlsViewModel")
@MainActor
struct EPUBReaderControlsViewModelTests {
    @Test("loadTableOfContents loads chapter entries from the bridge")
    func loadTableOfContentsLoadsBridgeEntries() async throws {
        let bridge = MockBookContentBridge(
            tocEntries: [
                ChapterEntry(title: "Intro", href: "intro.xhtml"),
                ChapterEntry(title: "Methods", href: "methods.xhtml", level: 1),
            ]
        )
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)

        await viewModel.loadTableOfContents()

        #expect(viewModel.tocEntries == bridge.tocEntries)
        #expect(viewModel.tocErrorMessage == nil)
    }

    @Test("performSearch trims the query and stores results")
    func performSearchTrimsQueryAndStoresResults() async throws {
        let bridge = MockBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "semantic search",
                    chapterTitle: "Results",
                    chapterHref: "results.xhtml",
                    textBefore: "Testing ",
                    textAfter: " with context",
                    progression: 0.42
                )
            ]
        )
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "  semantic search  "

        await viewModel.performSearch()

        #expect(bridge.recordedQueries == ["semantic search"])
        #expect(viewModel.searchResults == bridge.stubSearchResults)
        #expect(viewModel.searchErrorMessage == nil)
    }

    @Test("performSearch clears stale results when the query is blank")
    func performSearchClearsResultsForBlankQuery() async throws {
        let bridge = MockBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "prior result",
                    chapterTitle: "Results",
                    chapterHref: "results.xhtml"
                )
            ]
        )
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "result"
        await viewModel.performSearch()

        viewModel.searchQuery = "   "
        await viewModel.performSearch()

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.searchErrorMessage == nil)
        #expect(bridge.recordedQueries == ["result"])
    }

    @Test("performSearch captures bridge failures without keeping stale results")
    func performSearchCapturesFailures() async throws {
        let bridge = MockBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "prior result",
                    chapterTitle: "Results",
                    chapterHref: "results.xhtml"
                )
            ]
        )
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "result"
        await viewModel.performSearch()

        bridge.searchError = MockError.searchFailed
        viewModel.searchQuery = "broken"
        await viewModel.performSearch()

        #expect(viewModel.searchResults.isEmpty)
        #expect(
            viewModel.searchErrorMessage
                == AppLocalization.string("errors.reader.search_failed")
        )
        #expect(bridge.recordedQueries == ["result", "broken"])
    }

    @Test("performSearch prefers the localized fallback over raw bridge diagnostics")
    func performSearchPrefersFallbackOverLocalizedBridgeError() async {
        let bridge = MockBookContentBridge()
        bridge.searchError = LocalizedBridgeMockError.failed
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "broken"

        await viewModel.performSearch()

        #expect(
            viewModel.searchErrorMessage
                == AppLocalization.string("errors.reader.search_failed")
        )
    }

    @Test("loadTableOfContents maps failures to a localized reader message")
    func loadTableOfContentsCapturesFailures() async {
        let bridge = MockBookContentBridge()
        bridge.tocError = MockError.searchFailed
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)

        await viewModel.loadTableOfContents()

        #expect(viewModel.tocEntries.isEmpty)
        #expect(
            viewModel.tocErrorMessage
                == AppLocalization.string("reader.toc.load_failed")
        )
    }

    @Test("loadTableOfContents prefers the localized fallback over raw bridge diagnostics")
    func loadTableOfContentsPrefersFallbackOverLocalizedBridgeError() async {
        let bridge = MockBookContentBridge()
        bridge.tocError = LocalizedBridgeMockError.failed
        let viewModel = EPUBReaderControlsViewModel(bridge: bridge)

        await viewModel.loadTableOfContents()

        #expect(
            viewModel.tocErrorMessage
                == AppLocalization.string("reader.toc.load_failed")
        )
    }
}

private enum MockError: Error {
    case searchFailed
}

private enum LocalizedBridgeMockError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Search failed: underlying English diagnostics"
    }
}

private final class MockBookContentBridge: BookContentBridge, @unchecked Sendable {
    let title: String = "Stub EPUB"
    let tocEntries: [ChapterEntry]
    let stubSearchResults: [ContentSearchResult]
    var tocError: Error?
    var searchError: Error?
    private(set) var recordedQueries: [String] = []

    init(
        tocEntries: [ChapterEntry] = [],
        searchResults: [ContentSearchResult] = []
    ) {
        self.tocEntries = tocEntries
        self.stubSearchResults = searchResults
    }

    var tableOfContents: [ChapterEntry] {
        get async throws {
            if let tocError {
                throw tocError
            }
            return tocEntries
        }
    }

    func extractChapterContent(href: String) async throws -> String {
        ""
    }

    func extractFullText() async throws -> String {
        ""
    }

    func searchContent(query: String) async throws -> [ContentSearchResult] {
        recordedQueries.append(query)
        if let searchError {
            throw searchError
        }
        return stubSearchResults
    }
}
