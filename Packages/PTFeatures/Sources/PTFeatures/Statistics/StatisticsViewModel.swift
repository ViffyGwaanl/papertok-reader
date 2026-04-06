import Foundation
import Observation

@MainActor @Observable
public final class StatisticsViewModel {
    public var totalReadingTimeSeconds: Int = 0
    public var totalBooks: Int = 0
    public var totalNotes: Int = 0
    public var dailyReadingData: [String: Int] = [:]
    public var isLoading: Bool = false

    private let readingTimeDAO: ReadingTimeDAO
    private let bookDAO: BookDAO
    private let noteDAO: BookNoteDAO

    public init(database: AppDatabase) {
        self.readingTimeDAO = ReadingTimeDAO(database: database)
        self.bookDAO = BookDAO(database: database)
        self.noteDAO = BookNoteDAO(database: database)
    }

    public func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        totalReadingTimeSeconds = (try? await readingTimeDAO.totalReadingTimeAllBooks()) ?? 0
        totalBooks = (try? await bookDAO.fetchAll())?.count ?? 0
        let stats = try? await noteDAO.countNotesAndBooks()
        totalNotes = stats?.0 ?? 0

        // Load 91 days of daily reading data for heatmap
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let startString = DateFormatting.dateOnly.string(from: startDate)
        let endString = DateFormatting.dateOnly.string(from: today)
        if let rawData = try? await readingTimeDAO.dailyReadingData(from: startString, to: endString) {
            // Convert seconds to minutes
            var minuteData: [String: Int] = [:]
            for (date, seconds) in rawData {
                minuteData[date] = seconds / 60
            }
            dailyReadingData = minuteData
        }
    }

    public var formattedReadingTime: String {
        DateFormatting.formatDuration(seconds: totalReadingTimeSeconds)
    }
}
