import Foundation
import Testing
@testable import PTFeatures

@Suite("StatisticsViewModel")
@MainActor
struct StatisticsViewModelTests {
    @Test("loadStats computes streaks completion and daily highlight")
    func loadStatsComputesStreaksCompletionAndDailyHighlight() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let noteDAO = BookNoteDAO(database: database)
        let readingTimeDAO = ReadingTimeDAO(database: database)

        var almostDone = Book.placeholder(title: "Almost Done", filePath: "/almost.epub")
        almostDone.readingPercentage = 0.82
        let completionBook = try await bookDAO.save(almostDone)
        let completionBookID = try #require(completionBook.id)

        let highlightBook = try await bookDAO.save(Book.placeholder(title: "Highlight Book", filePath: "/highlight.epub"))
        let highlightBookID = try #require(highlightBook.id)

        for (date, minutes) in [("2026-03-28", 20), ("2026-03-29", 25), ("2026-03-30", 10), ("2026-03-31", 15), ("2026-04-05", 40), ("2026-04-06", 35), ("2026-04-07", 30)] {
            _ = try await readingTimeDAO.save(
                ReadingTime(bookId: completionBookID, date: date, readingTime: minutes * 60)
            )
        }

        _ = try await noteDAO.save(
            BookNote(
                bookId: completionBookID,
                content: "Earlier highlight",
                cfi: "epubcfi(/6/2)",
                chapter: "Intro",
                type: "highlight",
                color: "yellow",
                readerNote: nil,
                createTime: makeDate("2026-04-04"),
                updateTime: makeDate("2026-04-04")
            )
        )
        _ = try await noteDAO.save(
            BookNote(
                bookId: highlightBookID,
                content: "Daily highlight choice",
                cfi: "epubcfi(/6/6)",
                chapter: "Discussion",
                type: "highlight",
                color: "blue",
                readerNote: "Keep this for later.",
                createTime: makeDate("2026-04-07"),
                updateTime: makeDate("2026-04-07")
            )
        )

        let suiteName = "StatisticsViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let viewModel = StatisticsViewModel(
            database: database,
            tilePreferencesStore: StatisticsTilePreferencesStore(defaults: defaults, key: "tiles"),
            calendar: calendar,
            nowProvider: { self.makeDate("2026-04-07") },
            randomIndexProvider: { upperBound in upperBound - 1 }
        )

        await viewModel.loadStats()

        #expect(viewModel.currentStreakDays == 3)
        #expect(viewModel.longestStreakDays == 4)
        #expect(viewModel.nearlyFinishedBooks.map(\.title) == ["Almost Done"])
        let highlight = try #require(viewModel.dailyHighlight)
        #expect(highlight.bookTitle == "Highlight Book")
        #expect(highlight.note.content == "Daily highlight choice")
        #expect(viewModel.trendPoints.count == 7)
        #expect(viewModel.trendPoints.last?.minutes == 30)
    }

    @Test("tile preferences persist order and visibility")
    func tilePreferencesPersistOrderAndVisibility() throws {
        let suiteName = "StatisticsTilePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StatisticsTilePreferencesStore(defaults: defaults, key: "tiles")
        let initial = store.loadTiles()
        #expect(initial.contains(.readingTime))
        #expect(initial.contains(.dailyHighlight))

        let reordered: [StatisticsDashboardTile] = [.dailyHighlight, .currentStreak, .readingTime]
        store.saveTiles(reordered)

        #expect(store.loadTiles() == reordered)
    }

    @Test("longest streak keeps full history beyond heatmap window")
    func longestStreakKeepsFullHistoryBeyondHeatmapWindow() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let readingTimeDAO = ReadingTimeDAO(database: database)
        let book = try await bookDAO.save(Book.placeholder(title: "History", filePath: "/history.epub"))
        let bookID = try #require(book.id)

        for date in ["2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06"] {
            _ = try await readingTimeDAO.save(ReadingTime(bookId: bookID, date: date, readingTime: 20 * 60))
        }
        for date in ["2026-04-06", "2026-04-07"] {
            _ = try await readingTimeDAO.save(ReadingTime(bookId: bookID, date: date, readingTime: 25 * 60))
        }

        let viewModel = makeViewModel(database: database)
        await viewModel.loadStats()

        #expect(viewModel.currentStreakDays == 2)
        #expect(viewModel.longestStreakDays == 6)
    }

    @Test("year trends keep months beyond the heatmap window")
    func yearTrendsKeepMonthsBeyondTheHeatmapWindow() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let readingTimeDAO = ReadingTimeDAO(database: database)
        let book = try await bookDAO.save(Book.placeholder(title: "Yearly", filePath: "/yearly.epub"))
        let bookID = try #require(book.id)

        for (date, minutes) in [("2025-11-15", 45), ("2026-04-07", 30)] {
            _ = try await readingTimeDAO.save(ReadingTime(bookId: bookID, date: date, readingTime: minutes * 60))
        }

        let viewModel = makeViewModel(database: database)
        await viewModel.loadStats()
        viewModel.trendRange = .year

        #expect(viewModel.trendPoints.first(where: { $0.label == "Nov" })?.minutes == 45)
        #expect(viewModel.trendPoints.last?.minutes == 30)
    }

    @Test("per-book breakdown follows the selected trend range")
    func perBookBreakdownFollowsTheSelectedTrendRange() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let readingTimeDAO = ReadingTimeDAO(database: database)

        let systemsBook = try await bookDAO.save(Book.placeholder(title: "Distributed Systems", filePath: "/systems.epub"))
        let systemsBookID = try #require(systemsBook.id)
        let aiBook = try await bookDAO.save(Book.placeholder(title: "Applied AI", filePath: "/ai.epub"))
        let aiBookID = try #require(aiBook.id)

        for (bookId, date, minutes) in [
            (systemsBookID, "2026-04-05", 45),
            (systemsBookID, "2026-04-07", 30),
            (aiBookID, "2026-04-06", 20),
            (aiBookID, "2026-04-07", 15),
        ] {
            _ = try await readingTimeDAO.save(ReadingTime(bookId: bookId, date: date, readingTime: minutes * 60))
        }

        let viewModel = makeViewModel(database: database)
        await viewModel.loadStats()

        let breakdown = try #require(viewModel.perBookTrendBreakdowns.first)
        #expect(breakdown.bookTitle == "Distributed Systems")
        #expect(breakdown.totalMinutes == 75)
        #expect(breakdown.points.last?.minutes == 30)

        let aiBreakdown = try #require(viewModel.perBookTrendBreakdowns.first(where: { $0.bookTitle == "Applied AI" }))
        #expect(aiBreakdown.totalMinutes == 35)
        #expect(aiBreakdown.points[aiBreakdown.points.count - 2].minutes == 20)
        #expect(aiBreakdown.points.last?.minutes == 15)
    }

    @Test("weekly and monthly summaries compute correctly")
    func weeklyAndMonthlySummaries() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        let readingTimeDAO = ReadingTimeDAO(database: database)
        let book = try await bookDAO.save(Book.placeholder(title: "Summary Book", filePath: "/summary.epub"))
        let bookID = try #require(book.id)

        // 3 active days in the last 7 days: Apr 5, 6, 7
        for (date, minutes) in [("2026-04-05", 40), ("2026-04-06", 35), ("2026-04-07", 30)] {
            _ = try await readingTimeDAO.save(ReadingTime(bookId: bookID, date: date, readingTime: minutes * 60))
        }
        // 1 active day in the 8-30 day window: Mar 15
        _ = try await readingTimeDAO.save(ReadingTime(bookId: bookID, date: "2026-03-15", readingTime: 60 * 60))

        let viewModel = makeViewModel(database: database)
        await viewModel.loadStats()

        let weekly = viewModel.weeklySummary
        #expect(weekly.totalMinutes == 105)
        #expect(weekly.activeDays == 3)
        #expect(weekly.dailyAverageMinutes == 15) // 105 / 7

        let monthly = viewModel.monthlySummary
        #expect(monthly.totalMinutes == 165) // 105 + 60
        #expect(monthly.activeDays == 4)
        #expect(monthly.dailyAverageMinutes == 5) // 165 / 30
    }

    @Test("period summary formattedTotal formats hours and minutes")
    func periodSummaryFormattedTotal() {
        let shortSummary = StatisticsPeriodSummary(periodDays: 7, totalMinutes: 45, activeDays: 3, dailyAverageMinutes: 6)
        #expect(shortSummary.formattedTotal == "45m")

        let longSummary = StatisticsPeriodSummary(periodDays: 30, totalMinutes: 150, activeDays: 10, dailyAverageMinutes: 5)
        #expect(longSummary.formattedTotal == "2h 30m")

        let exactHours = StatisticsPeriodSummary(periodDays: 7, totalMinutes: 120, activeDays: 5, dailyAverageMinutes: 17)
        #expect(exactHours.formattedTotal == "2h")
    }

    private func makeDate(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)!
    }

    private func makeViewModel(database: AppDatabase) -> StatisticsViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let suiteName = "StatisticsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return StatisticsViewModel(
            database: database,
            tilePreferencesStore: StatisticsTilePreferencesStore(defaults: defaults, key: "tiles"),
            calendar: calendar,
            nowProvider: { self.makeDate("2026-04-07") },
            randomIndexProvider: { upperBound in max(upperBound - 1, 0) }
        )
    }
}
