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
    private func makeViewModel(api: any PaperTokAPIProtocol = MockPaperTokAPI()) -> PapersViewModel {
        let suiteName = "PapersViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return PapersViewModel(api: api, userDefaults: userDefaults)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        return components.date!
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

    @Test("Default day filter is 'latest' (reverse-chronological, no day lock)")
    @MainActor
    func defaultDayFilterIsLatest() {
        let vm = makeViewModel()
        #expect(vm.dayFilter == "latest")
        #expect(vm.customDate == nil)
        #expect(!vm.hasCustomDateFilter)
    }

    @Test("Initial loadMore passes the 'latest' day filter to the API")
    @MainActor
    func initialLoadUsesLatestDayFilter() async {
        let api = RecordingPaperTokAPI()
        let vm = makeViewModel(api: api)
        await vm.loadMore(reset: true)
        #expect(await api.requestedDaysSnapshot() == ["latest"])
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

    @Test("applyCustomDate activates custom date and reloads with yyyy-MM-dd day")
    @MainActor
    func applyCustomDateReloadsWithFormattedDay() async {
        let api = RecordingPaperTokAPI()
        let vm = makeViewModel(api: api)
        let date = makeDate(year: 2026, month: 4, day: 7)

        await vm.applyCustomDate(date)

        #expect(vm.dayFilter == "2026-04-07")
        #expect(vm.hasCustomDateFilter)
        #expect(vm.customDate != nil)
        #expect(await api.requestedDaysSnapshot() == ["2026-04-07"])
    }

    @Test("preset day filters clear custom date and keep latest/all API values")
    @MainActor
    func presetDayFiltersClearCustomDate() async {
        let api = RecordingPaperTokAPI()
        let vm = makeViewModel(api: api)

        await vm.applyCustomDate(makeDate(year: 2026, month: 4, day: 7))
        await vm.applyDayFilter("latest")
        #expect(vm.dayFilter == "latest")
        #expect(vm.customDate == nil)
        #expect(!vm.hasCustomDateFilter)

        await vm.applyDayFilter("all")
        #expect(vm.dayFilter == "all")
        #expect(vm.customDate == nil)
        #expect(await api.requestedDaysSnapshot() == ["2026-04-07", "latest", "all"])
    }

    @Test("applyLanguage reloads papers using the selected language")
    @MainActor
    func applyLanguageReloadsWithSelectedLanguage() async {
        let api = RecordingPaperTokAPI()
        let vm = makeViewModel(api: api)

        await vm.loadMore(reset: true)
        await vm.applyLanguage("en")

        #expect(vm.language == "en")
        #expect(await api.requestedLanguagesSnapshot() == ["zh", "en"])
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

private actor RecordingPaperTokAPI: PaperTokAPIProtocol {
    private var requestedDays: [String?] = []
    private var requestedLanguages: [String] = []

    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard] {
        requestedDays.append(day)
        requestedLanguages.append(language)
        return []
    }

    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail {
        throw URLError(.notConnectedToInternet)
    }

    func requestedDaysSnapshot() -> [String?] {
        requestedDays
    }

    func requestedLanguagesSnapshot() -> [String] {
        requestedLanguages
    }
}
