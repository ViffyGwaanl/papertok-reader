import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("PDFReaderControlsViewModel")
@MainActor
struct PDFReaderControlsViewModelTests {
    @Test("loadTableOfContents loads chapter entries from the bridge")
    func loadTableOfContentsLoadsBridgeEntries() async throws {
        let bridge = MockPDFBookContentBridge(
            tocEntries: [
                ChapterEntry(title: "Pages 1-5", href: "pages:0-4"),
                ChapterEntry(title: "Pages 6-10", href: "pages:5-9", level: 1),
            ]
        )
        let viewModel = PDFReaderControlsViewModel(bridge: bridge)

        await viewModel.loadTableOfContents()

        #expect(viewModel.tocEntries == bridge.tocEntries)
        #expect(viewModel.tocErrorMessage == nil)
    }

    @Test("performSearch trims the query and stores results")
    func performSearchTrimsQueryAndStoresResults() async throws {
        let bridge = MockPDFBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "vector search",
                    chapterTitle: "Page 3",
                    chapterHref: "pages:2-2",
                    textBefore: "Native ",
                    textAfter: " for PDFs",
                    progression: 0.25
                )
            ]
        )
        let viewModel = PDFReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "  vector search  "

        await viewModel.performSearch()

        #expect(bridge.recordedQueries == ["vector search"])
        #expect(viewModel.searchResults == bridge.stubSearchResults)
        #expect(viewModel.searchErrorMessage == nil)
    }

    @Test("performSearch clears stale results when the query is blank")
    func performSearchClearsResultsForBlankQuery() async throws {
        let bridge = MockPDFBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "prior result",
                    chapterTitle: "Page 2",
                    chapterHref: "pages:1-1"
                )
            ]
        )
        let viewModel = PDFReaderControlsViewModel(bridge: bridge)
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
        let bridge = MockPDFBookContentBridge(
            searchResults: [
                ContentSearchResult(
                    text: "prior result",
                    chapterTitle: "Page 2",
                    chapterHref: "pages:1-1"
                )
            ]
        )
        let viewModel = PDFReaderControlsViewModel(bridge: bridge)
        viewModel.searchQuery = "result"
        await viewModel.performSearch()

        bridge.searchError = MockPDFError.searchFailed
        viewModel.searchQuery = "broken"
        await viewModel.performSearch()

        #expect(viewModel.searchResults.isEmpty)
        #expect(
            viewModel.searchErrorMessage
                == AppLocalization.string("errors.reader.search_failed")
        )
        #expect(bridge.recordedQueries == ["result", "broken"])
    }

    @Test("loadTableOfContents maps failures to a localized reader message")
    func loadTableOfContentsCapturesFailures() async {
        let bridge = MockPDFBookContentBridge()
        bridge.tocError = MockPDFError.searchFailed
        let viewModel = PDFReaderControlsViewModel(bridge: bridge)

        await viewModel.loadTableOfContents()

        #expect(viewModel.tocEntries.isEmpty)
        #expect(
            viewModel.tocErrorMessage
                == AppLocalization.string("reader.toc.load_failed")
        )
    }
}

private enum MockPDFError: Error {
    case searchFailed
}

private final class MockPDFBookContentBridge: BookContentBridge, @unchecked Sendable {
    let title: String = "Stub PDF"
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
