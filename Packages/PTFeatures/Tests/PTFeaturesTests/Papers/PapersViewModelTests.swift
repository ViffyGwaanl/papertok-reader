import Testing
import Foundation
@testable import PTFeatures
@testable import PTNetworking

@Suite("PapersViewModel")
struct PapersViewModelTests {

    // MARK: - Helpers

    private func makeCard(id: Int, title: String = "Test Paper", extract: String = "Abstract...") throws -> PaperTokCard {
        let json = """
        {"pageid": \(id), "title": "\(title)", "extract": "\(extract)", "day": "2026-01-01"}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PaperTokCard.self, from: json)
    }

    @MainActor
    private func makeViewModel() -> PapersViewModel {
        PapersViewModel(api: MockPaperTokAPI(), userDefaults: UserDefaults(suiteName: "PapersViewModelTests")!)
    }

    // MARK: - Tests

    @Test("Initial state: cards empty, not loading, no error")
    @MainActor
    func initialState() {
        let vm = makeViewModel()
        #expect(vm.cards.isEmpty)
        #expect(!vm.isLoading)
        #expect(vm.error == nil)
        #expect(vm.searchQuery == "")
        #expect(!vm.likedOnly)
    }

    @Test("toggleLike adds and removes card ID from liked set")
    @MainActor
    func toggleLike() throws {
        let vm = makeViewModel()
        let card = try makeCard(id: 42)
        vm.cards = [card]

        vm.toggleLike(card)
        #expect(vm.likedIds.contains(42))
        #expect(vm.isLiked(card))

        vm.toggleLike(card)
        #expect(!vm.likedIds.contains(42))
        #expect(!vm.isLiked(card))
    }

    @Test("searchQuery filters visibleCards by title")
    @MainActor
    func searchFilter() throws {
        let vm = makeViewModel()
        vm.cards = [
            try makeCard(id: 1, title: "Swift Programming"),
            try makeCard(id: 2, title: "Python ML"),
        ]
        vm.searchQuery = "swift"
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }

    @Test("searchQuery filters visibleCards by extract")
    @MainActor
    func searchFilterByExtract() throws {
        let vm = makeViewModel()
        vm.cards = [
            try makeCard(id: 1, title: "Paper A", extract: "About transformers"),
            try makeCard(id: 2, title: "Paper B", extract: "About regression"),
        ]
        vm.searchQuery = "transformers"
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }

    @Test("likedOnly shows only liked cards")
    @MainActor
    func likedOnlyFilter() throws {
        let vm = makeViewModel()
        vm.cards = [
            try makeCard(id: 1, title: "Paper A"),
            try makeCard(id: 2, title: "Paper B"),
        ]
        vm.likedIds = [1]
        vm.likedOnly = true
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }

    @Test("Empty search query returns all cards")
    @MainActor
    func emptySearchReturnsAll() throws {
        let vm = makeViewModel()
        vm.cards = [
            try makeCard(id: 1, title: "A"),
            try makeCard(id: 2, title: "B"),
        ]
        vm.searchQuery = ""
        #expect(vm.visibleCards.count == 2)
    }

    @Test("Combined liked + search filter")
    @MainActor
    func combinedFilter() throws {
        let vm = makeViewModel()
        vm.cards = [
            try makeCard(id: 1, title: "Swift Concurrency"),
            try makeCard(id: 2, title: "Swift UI"),
            try makeCard(id: 3, title: "Python ML"),
        ]
        vm.likedIds = [1, 3]
        vm.likedOnly = true
        vm.searchQuery = "swift"
        #expect(vm.visibleCards.count == 1)
        #expect(vm.visibleCards.first?.id == 1)
    }
}

// MARK: - Mock

private struct MockPaperTokAPI: PaperTokAPIProtocol {
    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard] {
        []
    }

    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail {
        throw URLError(.notConnectedToInternet)
    }
}
