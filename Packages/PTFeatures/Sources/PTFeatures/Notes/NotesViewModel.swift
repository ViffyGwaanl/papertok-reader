import Foundation
import Observation

@MainActor @Observable
public final class NotesViewModel {
    public var notes: [BookNote] = []
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var filterBookId: Int64?

    private let noteDAO: BookNoteDAO

    public init(database: AppDatabase) {
        self.noteDAO = BookNoteDAO(database: database)
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
        } catch {
            notes = []
        }
    }

    public func deleteNote(id: Int64) async {
        do {
            try await noteDAO.delete(id: id)
            notes.removeAll { $0.id == id }
        } catch { }
    }

    public func noteStats() async -> (totalNotes: Int, booksWithNotes: Int) {
        (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
    }
}
