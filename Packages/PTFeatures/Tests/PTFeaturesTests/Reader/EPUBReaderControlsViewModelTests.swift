import Foundation
import Testing
@testable import PTFeatures
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
        #expect(viewModel.searchErrorMessage == MockError.searchFailed.localizedDescription)
        #expect(bridge.recordedQueries == ["result", "broken"])
    }
}

private enum MockError: Error {
    case searchFailed
}

private final class MockBookContentBridge: BookContentBridge, @unchecked Sendable {
    let title: String = "Stub EPUB"
    let tocEntries: [ChapterEntry]
    let stubSearchResults: [ContentSearchResult]
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
        get async throws { tocEntries }
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
