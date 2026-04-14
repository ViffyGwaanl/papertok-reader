import Foundation
import PTCore

public enum StatisticsTrendRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .week: return AppLocalization.string("statistics.this_week")
        case .month: return AppLocalization.string("statistics.this_month")
        case .year: return AppLocalization.string("statistics.this_year")
        }
    }
}

public struct StatisticsTrendPoint: Equatable, Sendable, Identifiable {
    public let dateKey: String
    public let label: String
    public let minutes: Int

    public var id: String { dateKey }

    public init(dateKey: String, label: String, minutes: Int) {
        self.dateKey = dateKey
        self.label = label
        self.minutes = minutes
    }
}

public struct StatisticsBookTrendBreakdown: Equatable, Sendable, Identifiable {
    public let bookId: Int64
    public let bookTitle: String
    public let totalMinutes: Int
    public let points: [StatisticsTrendPoint]

    public var id: Int64 { bookId }

    public init(bookId: Int64, bookTitle: String, totalMinutes: Int, points: [StatisticsTrendPoint]) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.totalMinutes = totalMinutes
        self.points = points
    }
}

public struct StatisticsDailyHighlight: Equatable, Sendable {
    public let bookId: Int64
    public let bookTitle: String
    public let note: BookNote

    public init(bookId: Int64, bookTitle: String, note: BookNote) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.note = note
    }
}

public struct StatisticsPeriodSummary: Equatable, Sendable {
    public let periodDays: Int
    public let totalMinutes: Int
    public let activeDays: Int
    public let dailyAverageMinutes: Int

    public init(periodDays: Int, totalMinutes: Int, activeDays: Int, dailyAverageMinutes: Int) {
        self.periodDays = periodDays
        self.totalMinutes = totalMinutes
        self.activeDays = activeDays
        self.dailyAverageMinutes = dailyAverageMinutes
    }

    public var formattedTotal: String {
        Self.durationFormatter.string(from: TimeInterval(totalMinutes * 60)) ?? "\(totalMinutes)"
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        return formatter
    }()
}

public enum StatisticsDashboardTile: String, CaseIterable, Identifiable, Sendable {
    case readingTime
    case totalBooks
    case totalNotes
    case currentStreak
    case longestStreak
    case dailyHighlight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .readingTime: return AppLocalization.string("statistics.reading_time_total")
        case .totalBooks: return AppLocalization.string("statistics.total_books")
        case .totalNotes: return AppLocalization.string("statistics.total_notes")
        case .currentStreak: return AppLocalization.string("statistics.streak")
        case .longestStreak: return AppLocalization.string("statistics.best_streak")
        case .dailyHighlight: return AppLocalization.string("statistics.daily_highlight")
        }
    }
}

public final class StatisticsTilePreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "statistics.dashboard.tiles") {
        self.defaults = defaults
        self.key = key
    }

    public func loadTiles() -> [StatisticsDashboardTile] {
        guard let rawValues = defaults.array(forKey: key) as? [String], rawValues.isEmpty == false else {
            return StatisticsDashboardTile.allCases
        }

        let restored = rawValues.compactMap(StatisticsDashboardTile.init(rawValue:))
        return restored.isEmpty ? StatisticsDashboardTile.allCases : restored
    }

    public func saveTiles(_ tiles: [StatisticsDashboardTile]) {
        defaults.set(tiles.map(\.rawValue), forKey: key)
    }
}

enum StatisticsDateKeyFormatter {
    static func make(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

enum StatisticsStreakCalculator {
    static func calculate(
        dailyReadingData: [String: Int],
        calendar: Calendar,
        today: Date
    ) -> (current: Int, longest: Int) {
        let activeDates: Set<String> = Set(
            dailyReadingData.compactMap { key, minutes in
                guard minutes > 0 else { return nil }
                return key
            }
        )

        let formatter = StatisticsDateKeyFormatter.make(calendar: calendar)
        var currentStreak = 0
        var cursor = calendar.startOfDay(for: today)

        while activeDates.contains(formatter.string(from: cursor)) {
            currentStreak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        var longestStreak = 0
        var runningStreak = 0
        let sortedKeys = activeDates.sorted()
        var previousDate: Date?

        for key in sortedKeys {
            guard let currentDate = formatter.date(from: key) else { continue }
            if let previousDate,
               let delta = calendar.dateComponents([.day], from: previousDate, to: currentDate).day,
               delta == 1 {
                runningStreak += 1
            } else {
                runningStreak = 1
            }
            longestStreak = max(longestStreak, runningStreak)
            previousDate = currentDate
        }

        return (currentStreak, longestStreak)
    }
}
