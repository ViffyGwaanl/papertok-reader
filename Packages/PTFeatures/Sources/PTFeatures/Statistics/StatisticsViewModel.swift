import Foundation
import Observation

@Observable
public final class StatisticsViewModel: @unchecked Sendable {
    public var totalReadingTimeSeconds: Int = 0
    public var totalBooks: Int = 0
    public var totalNotes: Int = 0
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
    }

    public var formattedReadingTime: String {
        DateFormatting.formatDuration(seconds: totalReadingTimeSeconds)
    }
}
