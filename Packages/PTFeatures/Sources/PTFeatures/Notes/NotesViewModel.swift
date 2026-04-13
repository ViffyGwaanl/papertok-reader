import Foundation
import Observation
import PTCore

public enum NotesFilterType: String, CaseIterable, Identifiable, Sendable {
    case all
    case highlight
    case bookmark
    case note

    public var id: String { rawValue }

    public var displayNameKey: String {
        switch self {
        case .all: return "notes.all"
        case .highlight: return "notes.highlights"
        case .bookmark: return "notes.bookmarks"
        case .note: return "notes.title"
        }
    }

    private var fallbackDisplayName: String {
        switch self {
        case .all: return "All"
        case .highlight: return "Highlights"
        case .bookmark: return "Bookmarks"
        case .note: return "Notes"
        }
    }

    public var displayName: String {
        AppLocalization.string(displayNameKey, value: fallbackDisplayName)
    }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .highlight: return "highlighter"
        case .bookmark: return "bookmark.fill"
        case .note: return "text.bubble.fill"
        }
    }
}

public enum NotesSortOrder: String, CaseIterable, Identifiable, Sendable {
    case dateDescending
    case dateAscending
    case chapter

    public var id: String { rawValue }

    public var displayNameKey: String {
        switch self {
        case .dateDescending: return "notes.sort_recent"
        case .dateAscending: return "notes.sort_oldest"
        case .chapter: return "notes.sort_chapter"
        }
    }

    private var fallbackDisplayName: String {
        switch self {
        case .dateDescending: return "Most Recent"
        case .dateAscending: return "Oldest First"
        case .chapter: return "By Chapter"
        }
    }

    public var displayName: String {
        AppLocalization.string(displayNameKey, value: fallbackDisplayName)
    }
}

@MainActor @Observable
public final class NotesViewModel {
    public var notes: [BookNote] = []
    public private(set) var groupedNotes: [NotesBookGroup] = []
    public private(set) var summary = NotesSummary()
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var filterBookId: Int64?
    public var filterType: NotesFilterType = .all {
        didSet { Task { await loadNotes() } }
    }
    public var sortOrder: NotesSortOrder = .dateDescending {
        didSet { groupedNotes = buildGroupsSynchronously(from: filteredNotes) }
    }

    private let noteDAO: BookNoteDAO
    private let bookDAO: BookDAO
    private var bookTitlesByID: [Int64: String] = [:]
    private var allLoadedNotes: [BookNote] = []

    public init(database: AppDatabase) {
        self.noteDAO = BookNoteDAO(database: database)
        self.bookDAO = BookDAO(database: database)
    }

    public func loadNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if !searchQuery.isEmpty {
                allLoadedNotes = try await noteDAO.search(keyword: searchQuery, bookId: filterBookId)
            } else if let bookId = filterBookId {
                allLoadedNotes = try await noteDAO.fetchByBookId(bookId)
            } else {
                allLoadedNotes = try await noteDAO.search(keyword: "")
            }
            let counts = (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
            summary = NotesSummary(totalNotes: counts.0, booksWithNotes: counts.1)

            let books = (try? await bookDAO.fetchAll()) ?? []
            bookTitlesByID = Dictionary(uniqueKeysWithValues: books.compactMap { book in
                guard let id = book.id else { return nil }
                return (id, book.title)
            })

            notes = filteredNotes
            groupedNotes = buildGroupsSynchronously(from: notes)
        } catch {
            allLoadedNotes = []
            notes = []
            groupedNotes = []
            summary = NotesSummary()
        }
    }

    public func deleteNote(id: Int64) async {
        do {
            try await noteDAO.delete(id: id)
            allLoadedNotes.removeAll { $0.id == id }
            notes = filteredNotes
            groupedNotes = buildGroupsSynchronously(from: notes)
            let counts = (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
            summary = NotesSummary(totalNotes: counts.0, booksWithNotes: counts.1)
        } catch { }
    }

    public func updateNote(_ note: BookNote) async {
        do {
            let saved = try await noteDAO.save(note)
            if let index = allLoadedNotes.firstIndex(where: { $0.id == saved.id }) {
                allLoadedNotes[index] = saved
            }
            notes = filteredNotes
            groupedNotes = buildGroupsSynchronously(from: notes)
        } catch { }
    }

    public func noteStats() async -> (totalNotes: Int, booksWithNotes: Int) {
        (try? await noteDAO.countNotesAndBooks()) ?? (0, 0)
    }

    public func export(format: NotesExportFormat) -> String {
        NotesExportBuilder.render(groups: groupedNotes, summary: summary, format: format)
    }

    private var filteredNotes: [BookNote] {
        let typeFiltered: [BookNote]
        switch filterType {
        case .all:
            typeFiltered = allLoadedNotes
        case .highlight:
            typeFiltered = allLoadedNotes.filter { $0.type.lowercased() == "highlight" }
        case .bookmark:
            typeFiltered = allLoadedNotes.filter { $0.type.lowercased() == "bookmark" }
        case .note:
            typeFiltered = allLoadedNotes.filter { $0.type.lowercased() == "note" }
        }
        return typeFiltered
    }

    private func buildGroupsSynchronously(from notes: [BookNote]) -> [NotesBookGroup] {
        return Dictionary(grouping: notes, by: \.bookId)
            .map { bookId, bookNotes in
                let sortedNotes: [BookNote]
                switch sortOrder {
                case .dateDescending:
                    sortedNotes = bookNotes.sorted { lhs, rhs in
                        (lhs.createTime ?? lhs.updateTime) > (rhs.createTime ?? rhs.updateTime)
                    }
                case .dateAscending:
                    sortedNotes = bookNotes.sorted { lhs, rhs in
                        (lhs.createTime ?? lhs.updateTime) < (rhs.createTime ?? rhs.updateTime)
                    }
                case .chapter:
                    sortedNotes = bookNotes.sorted { lhs, rhs in
                        LocalizedSort.isAscending(lhs.chapter, rhs.chapter)
                    }
                }
                let latestDate = sortedNotes.first.map { $0.createTime ?? $0.updateTime } ?? .distantPast
                let title = bookTitlesByID[bookId]
                    ?? String(
                        format: AppLocalization.string(
                            "notes.book_fallback_format",
                            value: "Book #%lld"
                        ),
                        locale: .autoupdatingCurrent,
                        bookId
                    )
                return NotesBookGroup(
                    bookId: bookId,
                    bookTitle: title,
                    notes: sortedNotes,
                    lastUpdatedAt: latestDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.lastUpdatedAt == rhs.lastUpdatedAt {
                    return LocalizedSort.isAscending(lhs.bookTitle, rhs.bookTitle)
                }
                return lhs.lastUpdatedAt > rhs.lastUpdatedAt
            }
    }
}
