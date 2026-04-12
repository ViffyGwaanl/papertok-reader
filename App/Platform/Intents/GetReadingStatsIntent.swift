import AppIntents
import Foundation
import PTCore

enum ReadingStatsScope: String, AppEnum {
    case today
    case week
    case month
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reading Stats Scope" }
    static var caseDisplayRepresentations: [ReadingStatsScope: DisplayRepresentation] {
        [
            .today: "Today",
            .week: "This Week",
            .month: "This Month",
            .all: "All Time",
        ]
    }
}

/// Siri Shortcut: "Get reading stats for [scope] in PaperTok"
struct GetReadingStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Reading Stats"
    static let description = IntentDescription(
        "Returns reading time, books read, notes captured, and current streak."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Scope", default: .today)
    var scope: ReadingStatsScope

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let database = try IntentDatabaseAccess.open()
        let bookDAO = BookDAO(database: database)
        let readingDAO = ReadingTimeDAO(database: database)

        let dailyTotals = try await readingDAO.dailyReadingData()
        let booksCount = try await bookDAO.fetchAll().count
        let notesCount = try await BookNoteDAO(database: database).countNotesAndBooks().0

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let todayKey = formatter.string(from: today)

        let secondsInScope: Int
        switch scope {
        case .today:
            secondsInScope = dailyTotals[todayKey] ?? 0
        case .week:
            secondsInScope = sum(dailyTotals: dailyTotals, since: calendar.date(byAdding: .day, value: -6, to: today), formatter: formatter)
        case .month:
            secondsInScope = sum(dailyTotals: dailyTotals, since: calendar.date(byAdding: .day, value: -29, to: today), formatter: formatter)
        case .all:
            secondsInScope = dailyTotals.values.reduce(0, +)
        }

        let streak = currentStreak(dailyTotals: dailyTotals, formatter: formatter, calendar: calendar, today: today)
        let hours = Double(secondsInScope) / 3600.0
        let formattedHours = String(format: "%.1f", hours)
        let scopeWord: String = {
            switch scope {
            case .today: return "today"
            case .week: return "this week"
            case .month: return "this month"
            case .all: return "in total"
            }
        }()

        let summary = """
        Reading time: \(formattedHours) hours \(scopeWord)
        Books in library: \(booksCount)
        Notes captured: \(notesCount)
        Current streak: \(streak) day\(streak == 1 ? "" : "s")
        """

        let dialog: IntentDialog = "You've read \(formattedHours) hours \(scopeWord)."
        return .result(value: summary, dialog: dialog)
    }

    private func sum(
        dailyTotals: [String: Int],
        since startDate: Date?,
        formatter: DateFormatter
    ) -> Int {
        guard let startDate else { return 0 }
        let startKey = formatter.string(from: startDate)
        return dailyTotals.reduce(0) { partial, entry in
            entry.key >= startKey ? partial + entry.value : partial
        }
    }

    private func currentStreak(
        dailyTotals: [String: Int],
        formatter: DateFormatter,
        calendar: Calendar,
        today: Date
    ) -> Int {
        var streak = 0
        var cursor = today
        while true {
            let key = formatter.string(from: cursor)
            if let value = dailyTotals[key], value > 0 {
                streak += 1
                guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = next
            } else {
                break
            }
        }
        return streak
    }
}
