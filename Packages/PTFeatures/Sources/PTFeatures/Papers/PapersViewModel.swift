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
    public var dayFilter = "latest"
    public private(set) var language: String
    public private(set) var customDate: Date?
    public var likedIds: Set<Int> = []

    // MARK: Dependencies

    private let api: any PaperTokAPIProtocol
    private let userDefaults: UserDefaults

    private static let likedIdsKey = "papertok_liked_ids"
    private static let presetDayFilters: Set<String> = ["all", "latest"]
    private static var filterCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    public init(
        api: any PaperTokAPIProtocol = PaperTokAPI(),
        language: String = "zh",
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.language = Self.normalizedLanguage(language)
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

    public var hasCustomDateFilter: Bool {
        customDate != nil && !Self.presetDayFilters.contains(dayFilter)
    }

    // MARK: Actions

    public func loadMore(reset: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        if reset { cards = [] }
        do {
            let fetched = try await api.fetchRandomPapers(
                limit: 20, language: language, day: dayFilter
            )
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
        customDate = Self.presetDayFilters.contains(filter) ? nil : Self.customDate(from: filter)
        await loadMore(reset: true)
    }

    public func applyCustomDate(_ date: Date) async {
        let normalizedDate = Self.normalizedDate(date)
        customDate = normalizedDate
        dayFilter = Self.apiDayString(from: normalizedDate)
        await loadMore(reset: true)
    }

    public func applyLanguage(_ language: String) async {
        let normalizedLanguage = Self.normalizedLanguage(language)
        guard self.language != normalizedLanguage else { return }
        self.language = normalizedLanguage
        await loadMore(reset: true)
    }

    private static func normalizedDate(_ date: Date) -> Date {
        let components = filterCalendar.dateComponents([.year, .month, .day], from: date)
        return filterCalendar.date(from: components) ?? date
    }

    private static func apiDayString(from date: Date) -> String {
        let components = filterCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func customDate(from filter: String) -> Date? {
        let parts = filter.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return filterCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func normalizedLanguage(_ language: String) -> String {
        language.lowercased() == "en" ? "en" : "zh"
    }
}
