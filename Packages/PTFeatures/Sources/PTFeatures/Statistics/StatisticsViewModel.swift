import Foundation
import Observation

@MainActor @Observable
public final class StatisticsViewModel {
    public var totalReadingTimeSeconds: Int = 0
    public var totalBooks: Int = 0
    public var totalNotes: Int = 0
    public var dailyReadingData: [String: Int] = [:]
    public private(set) var currentStreakDays: Int = 0
    public private(set) var longestStreakDays: Int = 0
    public private(set) var trendPoints: [StatisticsTrendPoint] = []
    public private(set) var perBookTrendBreakdowns: [StatisticsBookTrendBreakdown] = []
    public private(set) var nearlyFinishedBooks: [Book] = []
    public private(set) var dailyHighlight: StatisticsDailyHighlight?
    public private(set) var visibleTiles: [StatisticsDashboardTile]
    public var trendRange: StatisticsTrendRange = .week {
        didSet {
            rebuildTrendArtifacts()
        }
    }
    public var isLoading: Bool = false

    private let readingTimeDAO: ReadingTimeDAO
    private let bookDAO: BookDAO
    private let noteDAO: BookNoteDAO
    private let tilePreferencesStore: StatisticsTilePreferencesStore
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let randomIndexProvider: (Int) -> Int
    private var dailyReadingMinutesByBook: [Int64: [String: Int]] = [:]
    private var bookTitlesByID: [Int64: String] = [:]

    public init(
        database: AppDatabase,
        tilePreferencesStore: StatisticsTilePreferencesStore = StatisticsTilePreferencesStore(),
        calendar: Calendar = Calendar.current,
        nowProvider: @escaping () -> Date = Date.init,
        randomIndexProvider: @escaping (Int) -> Int = { upperBound in Int.random(in: 0 ..< upperBound) }
    ) {
        self.readingTimeDAO = ReadingTimeDAO(database: database)
        self.bookDAO = BookDAO(database: database)
        self.noteDAO = BookNoteDAO(database: database)
        self.tilePreferencesStore = tilePreferencesStore
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.randomIndexProvider = randomIndexProvider
        self.visibleTiles = tilePreferencesStore.loadTiles()
    }

    public func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        totalReadingTimeSeconds = (try? await readingTimeDAO.totalReadingTimeAllBooks()) ?? 0
        totalBooks = (try? await bookDAO.fetchAll())?.count ?? 0
        let stats = try? await noteDAO.countNotesAndBooks()
        totalNotes = stats?.0 ?? 0

        let today = nowProvider()
        // Keep full history in memory so year trends and longest streak stay accurate.
        dailyReadingData = ((try? await readingTimeDAO.dailyReadingData()) ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value / 60
        }
        dailyReadingMinutesByBook = ((try? await readingTimeDAO.dailyReadingDataByBook()) ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.reduce(into: [:]) { bookResult, dayEntry in
                bookResult[dayEntry.key] = dayEntry.value / 60
            }
        }

        let streaks = StatisticsStreakCalculator.calculate(
            dailyReadingData: dailyReadingData,
            calendar: calendar,
            today: today
        )
        currentStreakDays = streaks.current
        longestStreakDays = streaks.longest

        let books = (try? await bookDAO.fetchAll()) ?? []
        bookTitlesByID = Dictionary(uniqueKeysWithValues: books.compactMap { book in
            guard let id = book.id else { return nil }
            return (id, book.title)
        })
        nearlyFinishedBooks = books
            .filter { 0.6 ... 0.93 ~= $0.readingPercentage }
            .sorted { lhs, rhs in
                lhs.readingPercentage > rhs.readingPercentage
            }

        let allNotes = (try? await noteDAO.search(keyword: "")) ?? []
        let highlightNotes = allNotes
            .filter { $0.type.lowercased() == "highlight" }
            .sorted { lhs, rhs in
                let lhsDate = lhs.createTime ?? lhs.updateTime
                let rhsDate = rhs.createTime ?? rhs.updateTime
                return lhsDate < rhsDate
            }
        if highlightNotes.isEmpty {
            dailyHighlight = nil
        } else {
            let clampedIndex = max(0, min(randomIndexProvider(highlightNotes.count), highlightNotes.count - 1))
            let chosenNote = highlightNotes[clampedIndex]
            let bookTitle = books.first(where: { $0.id == chosenNote.bookId })?.title
                ?? AppLocalization.format(
                    "notes.book_fallback_format",
                    locale: displayLocale,
                    chosenNote.bookId
                )
            dailyHighlight = StatisticsDailyHighlight(bookId: chosenNote.bookId, bookTitle: bookTitle, note: chosenNote)
        }

        rebuildTrendArtifacts()
    }

    public var formattedReadingTime: String {
        DateFormatting.formatDuration(
            seconds: totalReadingTimeSeconds,
            locale: displayLocale
        )
    }

    /// Weekly reading summary: total minutes, daily average, and number of active days.
    public var weeklySummary: StatisticsPeriodSummary {
        buildPeriodSummary(days: 7)
    }

    /// Monthly reading summary: total minutes, daily average, and number of active days.
    public var monthlySummary: StatisticsPeriodSummary {
        buildPeriodSummary(days: 30)
    }

    private func buildPeriodSummary(days: Int) -> StatisticsPeriodSummary {
        let formatter = StatisticsDateKeyFormatter.make(calendar: calendar)
        let today = nowProvider()
        var totalMinutes = 0
        var activeDays = 0
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = formatter.string(from: date)
            let minutes = dailyReadingData[key] ?? 0
            totalMinutes += minutes
            if minutes > 0 { activeDays += 1 }
        }
        return StatisticsPeriodSummary(
            periodDays: days,
            totalMinutes: totalMinutes,
            activeDays: activeDays,
            dailyAverageMinutes: days > 0 ? totalMinutes / days : 0
        )
    }

    public func saveVisibleTiles(_ tiles: [StatisticsDashboardTile]) {
        visibleTiles = tiles
        tilePreferencesStore.saveTiles(tiles)
    }

    private func rebuildTrendArtifacts() {
        trendPoints = buildTrendPoints(from: dailyReadingData)
        perBookTrendBreakdowns = buildPerBookTrendBreakdowns()
    }

    private func buildTrendPoints(from dailyData: [String: Int]) -> [StatisticsTrendPoint] {
        let formatter = StatisticsDateKeyFormatter.make(calendar: calendar)
        return trendBuckets().map { bucket in
            StatisticsTrendPoint(
                dateKey: bucket.dateKey,
                label: bucket.label,
                minutes: minutes(in: bucket, dailyData: dailyData, formatter: formatter)
            )
        }
    }

    private func buildPerBookTrendBreakdowns() -> [StatisticsBookTrendBreakdown] {
        dailyReadingMinutesByBook.compactMap { bookId, dailyData in
            let points = buildTrendPoints(from: dailyData)
            let totalMinutes = points.reduce(into: 0) { partialResult, point in
                partialResult += point.minutes
            }
            guard totalMinutes > 0 else { return nil }
            return StatisticsBookTrendBreakdown(
                bookId: bookId,
                bookTitle: bookTitlesByID[bookId]
                    ?? AppLocalization.format(
                        "notes.book_fallback_format",
                        locale: displayLocale,
                        bookId
                    ),
                totalMinutes: totalMinutes,
                points: points
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalMinutes == rhs.totalMinutes {
                return LocalizedSort.isAscending(lhs.bookTitle, rhs.bookTitle)
            }
            return lhs.totalMinutes > rhs.totalMinutes
        }
    }

    private func trendBuckets() -> [StatisticsTrendBucket] {
        let formatter = StatisticsDateKeyFormatter.make(calendar: calendar)
        let today = nowProvider()

        switch trendRange {
        case .week:
            return stride(from: 6, through: 0, by: -1).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return StatisticsTrendBucket(
                    dateKey: formatter.string(from: date),
                    label: shortWeekday(for: date)
                )
            }
        case .month:
            return stride(from: 29, through: 0, by: -1).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return StatisticsTrendBucket(
                    dateKey: formatter.string(from: date),
                    label: dayLabel(for: date)
                )
            }
        case .year:
            let monthFormatter = DateFormatter()
            monthFormatter.calendar = calendar
            monthFormatter.locale = displayLocale
            monthFormatter.timeZone = calendar.timeZone
            monthFormatter.dateFormat = "MMM"
            return stride(from: 11, through: 0, by: -1).compactMap { offset in
                guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: today),
                      let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else {
                    return nil
                }
                return StatisticsTrendBucket(
                    dateKey: formatter.string(from: monthInterval.start),
                    label: monthFormatter.string(from: monthDate),
                    interval: monthInterval
                )
            }
        }
    }

    private func minutes(
        in bucket: StatisticsTrendBucket,
        dailyData: [String: Int],
        formatter: DateFormatter
    ) -> Int {
        if let interval = bucket.interval {
            return dailyData.reduce(into: 0) { partialResult, entry in
                guard let date = formatter.date(from: entry.key), interval.contains(date) else { return }
                partialResult += entry.value
            }
        }
        return dailyData[bucket.dateKey] ?? 0
    }

    private func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = displayLocale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = displayLocale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var displayLocale: Locale {
        calendar.locale ?? .autoupdatingCurrent
    }
}

private struct StatisticsTrendBucket {
    let dateKey: String
    let label: String
    let interval: DateInterval?

    init(dateKey: String, label: String, interval: DateInterval? = nil) {
        self.dateKey = dateKey
        self.label = label
        self.interval = interval
    }
}
