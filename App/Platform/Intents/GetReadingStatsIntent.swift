import AppIntents
import Foundation
import PTCore

enum ReadingStatsScope: String, AppEnum {
    case today
    case week
    case month
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "intent.get_stats.scope.type"
    }

    static var caseDisplayRepresentations: [ReadingStatsScope: DisplayRepresentation] {
        [
            .today: "common.today",
            .week: "common.this_week",
            .month: "statistics.this_month",
            .all: "statistics.all_time",
        ]
    }
}

/// Siri Shortcut: "Get reading stats for [scope] in PaperTok"
struct GetReadingStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.get_stats.title"
    static let description = IntentDescription(
        "intent.get_stats.description"
    )
    static let openAppWhenRun = false

    @Parameter(title: "intent.parameter.range", default: .today)
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
        let formattedHours = localizedDecimal(Double(secondsInScope) / 3600.0)
        let readingTimeLineKey: String = {
            switch scope {
            case .today: return "intent.get_stats.summary.reading_time.today_format"
            case .week: return "intent.get_stats.summary.reading_time.week_format"
            case .month: return "intent.get_stats.summary.reading_time.month_format"
            case .all: return "intent.get_stats.summary.reading_time.all_format"
            }
        }()
        let dialogKey: String = {
            switch scope {
            case .today: return "intent.get_stats.dialog.today_format"
            case .week: return "intent.get_stats.dialog.week_format"
            case .month: return "intent.get_stats.dialog.month_format"
            case .all: return "intent.get_stats.dialog.all_format"
            }
        }()

        let summaryLines = [
            AppLocalization.format(readingTimeLineKey, locale: .autoupdatingCurrent, formattedHours),
            AppLocalization.format("intent.get_stats.summary.books_count_format", locale: .autoupdatingCurrent, booksCount),
            AppLocalization.format("intent.get_stats.summary.notes_count_format", locale: .autoupdatingCurrent, notesCount),
            AppLocalization.format("intent.get_stats.summary.streak_format", locale: .autoupdatingCurrent, streak),
        ]
        let summary = summaryLines.joined(separator: "\n")

        let dialog = IntentDialog(stringLiteral: AppLocalization.format(
            dialogKey,
            locale: .autoupdatingCurrent,
            formattedHours
        ))
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

    private func localizedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
