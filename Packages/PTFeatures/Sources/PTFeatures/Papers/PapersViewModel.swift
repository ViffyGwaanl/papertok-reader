import Foundation
import Observation
import PTNetworking

// MARK: - PaperTokAPIProtocol

/// Protocol for PaperTok API to enable mock injection in tests.
public protocol PaperTokAPIProtocol: Sendable {
    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard]
    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail
}

extension PaperTokAPI: PaperTokAPIProtocol {}

// MARK: - PapersViewModel

@MainActor
@Observable
public final class PapersViewModel {
    // MARK: State

    public var cards: [PaperTokCard] = []
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var searchQuery = ""
    public var likedOnly = false
    public var dayFilter = "all"
    public var likedIds: Set<Int> = []

    // MARK: Dependencies

    private let api: any PaperTokAPIProtocol
    private let language: String
    private let userDefaults: UserDefaults

    private static let likedIdsKey = "papertok_liked_ids"

    public init(
        api: any PaperTokAPIProtocol = PaperTokAPI(),
        language: String = "zh",
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.language = language
        self.userDefaults = userDefaults
        if let saved = userDefaults.array(forKey: Self.likedIdsKey) as? [Int] {
            self.likedIds = Set(saved)
        }
    }

    // MARK: Computed

    public var visibleCards: [PaperTokCard] {
        let source = likedOnly ? cards.filter { likedIds.contains($0.id) } : cards
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return source }
        return source.filter { card in
            card.bestTitle.lowercased().contains(query)
                || card.extract.lowercased().contains(query)
                || (card.day ?? "").lowercased().contains(query)
        }
    }

    public func isLiked(_ card: PaperTokCard) -> Bool {
        likedIds.contains(card.id)
    }

    // MARK: Actions

    public func loadMore(reset: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        if reset { cards = [] }
        do {
            var fetched = try await api.fetchRandomPapers(
                limit: 20, language: language, day: dayFilter
            )
            // Fallback: if "latest" yields nothing, try "all"
            if reset, fetched.isEmpty, dayFilter == "latest" {
                fetched = try await api.fetchRandomPapers(
                    limit: 20, language: language, day: "all"
                )
            }
            cards.append(contentsOf: fetched)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    public func toggleLike(_ card: PaperTokCard) {
        if likedIds.contains(card.id) {
            likedIds.remove(card.id)
        } else {
            likedIds.insert(card.id)
        }
        userDefaults.set(Array(likedIds), forKey: Self.likedIdsKey)
    }

    public func applyDayFilter(_ filter: String) async {
        dayFilter = filter
        await loadMore(reset: true)
    }
}
