import Foundation
import Observation

@MainActor @Observable
public final class NotesViewModel {
    public var notes: [BookNote] = []
    public private(set) var groupedNotes: [NotesBookGroup] = []
    public private(set) var summary = NotesSummary()
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var filterBookId: Int64?

    private let noteDAO: BookNoteDAO
    private let bookDAO: BookDAO

    public init(database: AppDatabase) {
        self.noteDAO = BookNoteDAO(database: database)
        self.bookDAO = BookDAO(database: database)
    }

    public func loadNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if !searchQuery.isEmpty {
                notes = try await noteDAO.search(keyword: searchQuery, bookId: filterBookId)
            } else if let bookId = filterBookId {
                notes = try await noteDAO.fetchByBookId(bookId)
            } else {
                // Fetch all notes (no filter)
                notes = try await noteDAO.search(keyword: "")
            }
            let counts = (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
            summary = NotesSummary(totalNotes: counts.0, booksWithNotes: counts.1)
            groupedNotes = await buildGroups(from: notes)
        } catch {
            notes = []
            groupedNotes = []
            summary = NotesSummary()
        }
    }

    public func deleteNote(id: Int64) async {
        do {
            try await noteDAO.delete(id: id)
            notes.removeAll { $0.id == id }
            groupedNotes = await buildGroups(from: notes)
            let counts = (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
            summary = NotesSummary(totalNotes: counts.0, booksWithNotes: counts.1)
        } catch { }
    }

    public func noteStats() async -> (totalNotes: Int, booksWithNotes: Int) {
        (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
    }

    public func export(format: NotesExportFormat) -> String {
        NotesExportBuilder.render(groups: groupedNotes, summary: summary, format: format)
    }

    private func buildGroups(from notes: [BookNote]) async -> [NotesBookGroup] {
        let books = (try? await bookDAO.fetchAll()) ?? []
        let titlesByBookID: [Int64: String] = Dictionary(uniqueKeysWithValues: books.compactMap { book in
            guard let id = book.id else { return nil }
            return (id, book.title)
        })

        return Dictionary(grouping: notes, by: \.bookId)
            .map { bookId, bookNotes in
                let sortedNotes = bookNotes.sorted { lhs, rhs in
                    let lhsDate = lhs.createTime ?? lhs.updateTime
                    let rhsDate = rhs.createTime ?? rhs.updateTime
                    return lhsDate > rhsDate
                }
                let latestDate = sortedNotes.first.map { $0.createTime ?? $0.updateTime } ?? .distantPast
                let title = titlesByBookID[bookId] ?? "Book #\(bookId)"
                return NotesBookGroup(
                    bookId: bookId,
                    bookTitle: title,
                    notes: sortedNotes,
                    lastUpdatedAt: latestDate
                )
            }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }
}
