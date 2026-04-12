import Foundation
import Observation
import PTCore
import PTReader

@MainActor @Observable
public final class EPUBReaderAnnotationsViewModel {
    public let bookId: Int64
    public private(set) var notes: [BookNote] = []
    public private(set) var errorMessage: String?

    private let noteDAO: BookNoteDAO

    public init(bookId: Int64, database: AppDatabase) {
        self.bookId = bookId
        self.noteDAO = BookNoteDAO(database: database)
    }

    public func loadAnnotations() async {
        do {
            notes = try await noteDAO.fetchByBookId(bookId)
            errorMessage = nil
        } catch {
            notes = []
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func createAnnotation(
        selectedText: String,
        locatorString: String,
        chapterTitle: String,
        type: NoteType,
        color: HighlightColor,
        readerNote: String?
    ) async -> BookNote? {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard type == .bookmark || trimmedSelection.isEmpty == false else {
            errorMessage = "Highlights and notes require selected text."
            return nil
        }

        let timestamp = Date()
        let normalizedContent = normalizedContent(
            selectedText: selectedText,
            chapterTitle: chapterTitle,
            type: type
        )
        let note = BookNote(
            bookId: bookId,
            content: normalizedContent,
            cfi: locatorString,
            chapter: chapterTitle,
            type: type.rawValue,
            color: color.hex,
            readerNote: normalizedReaderNote(type: type, readerNote: readerNote),
            createTime: timestamp,
            updateTime: timestamp
        )
        return await save(note)
    }

    @discardableResult
    public func updateAnnotation(
        id: Int64,
        type: NoteType,
        color: HighlightColor,
        readerNote: String?
    ) async -> BookNote? {
        guard var existing = notes.first(where: { $0.id == id }) else {
            return nil
        }

        let existingType = NoteType(rawValue: existing.type) ?? .highlight
        if existingType == .bookmark && type != .bookmark {
            errorMessage = "Highlights and notes require selected text."
            return nil
        }

        existing.type = type.rawValue
        existing.color = color.hex
        existing.readerNote = normalizedReaderNote(type: type, readerNote: readerNote)
        existing.updateTime = Date()
        return await save(existing)
    }

    public func deleteAnnotation(id: Int64) async {
        do {
            try await noteDAO.delete(id: id)
            notes.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func note(matchingDecorationID decorationID: String) -> BookNote? {
        guard let id = Int64(decorationID) else {
            return nil
        }
        return notes.first { $0.id == id }
    }

    private func save(_ note: BookNote) async -> BookNote? {
        do {
            let saved = try await noteDAO.save(note)
            await loadAnnotations()
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func normalizedReaderNote(type: NoteType, readerNote: String?) -> String? {
        guard type == .note else {
            return nil
        }

        let trimmed = readerNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedContent(
        selectedText: String,
        chapterTitle: String,
        type: NoteType
    ) -> String {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSelection.isEmpty == false {
            return trimmedSelection
        }

        guard type == .bookmark else {
            return trimmedSelection
        }

        let trimmedChapter = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedChapter.isEmpty ? "Bookmark" : trimmedChapter
    }
}
