import Foundation
import Observation
import PTReader

@MainActor @Observable
public final class ReaderControlsViewModel {
    public var showTOC: Bool = false
    public var showSearch: Bool = false
    public var searchQuery: String = ""

    public private(set) var tocEntries: [ChapterEntry] = []
    public private(set) var searchResults: [ContentSearchResult] = []
    public private(set) var isLoadingTOC: Bool = false
    public private(set) var isSearching: Bool = false
    public private(set) var tocErrorMessage: String?
    public private(set) var searchErrorMessage: String?

    private let bridge: any BookContentBridge

    public init(bridge: any BookContentBridge) {
        self.bridge = bridge
    }

    public func loadTableOfContents() async {
        isLoadingTOC = true
        defer { isLoadingTOC = false }

        do {
            tocEntries = try await bridge.tableOfContents
            tocErrorMessage = nil
        } catch {
            tocEntries = []
            tocErrorMessage = error.localizedDescription
        }
    }

    public func performSearch() async {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = trimmedQuery

        guard trimmedQuery.isEmpty == false else {
            searchResults = []
            searchErrorMessage = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await bridge.searchContent(query: trimmedQuery)
            searchErrorMessage = nil
        } catch {
            searchResults = []
            searchErrorMessage = error.localizedDescription
        }
    }
}
