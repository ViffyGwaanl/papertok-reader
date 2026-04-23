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
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.reader.annotation_load_failed"
            )
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
            errorMessage = AppLocalization.string("errors.reader.selected_text_required")
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
            errorMessage = AppLocalization.string("errors.reader.selected_text_required")
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
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.reader.annotation_delete_failed"
            )
        }
    }

    public func note(matchingDecorationID decorationID: String) -> BookNote? {
        guard let id = Int64(decorationID) else {
            return nil
        }
        return notes.first { $0.id == id }
    }

    /// Routes an EPUB decoration tap (from Readium's
    /// `observeDecorationInteractions`) to the shared context-menu coordinator
    /// so the reader surfaces the existing-annotation edit sheet. Mirrors the
    /// PDF view-model's `handleAnnotationTap(id:coordinator:)` for parity.
    @discardableResult
    public func handleAnnotationTap(
        id: Int64,
        coordinator: ContextMenuCoordinator
    ) -> Bool {
        guard let note = notes.first(where: { $0.id == id }) else {
            return false
        }
        coordinator.showAnnotationEdit(note: note)
        return true
    }

    /// Convenience overload that accepts a Readium `Decoration.id` string and
    /// maps it through `note(matchingDecorationID:)` before routing the tap.
    @discardableResult
    public func handleAnnotationTap(
        decorationID: String,
        coordinator: ContextMenuCoordinator
    ) -> Bool {
        guard let note = note(matchingDecorationID: decorationID) else {
            return false
        }
        coordinator.showAnnotationEdit(note: note)
        return true
    }

    /// Whether a bookmark already exists for the locator anchored at the
    /// supplied stored string. Used by the reader toolbar to pick the
    /// filled vs. outline glyph and the correct accessibility label.
    public func isBookmarked(locatorString: String) -> Bool {
        notes.contains { note in
            note.type == NoteType.bookmark.rawValue && note.cfi == locatorString
        }
    }

    /// One-tap bookmark toggle used by the reader toolbar. Creates a
    /// `NoteType.bookmark` row via the shared annotation flow when none
    /// exists for the supplied locator, otherwise deletes the existing
    /// matching bookmark. The in-memory `notes` list is kept in sync.
    public func toggleBookmark(locatorString: String, chapterTitle: String) async {
        if let existing = notes.first(where: {
            $0.type == NoteType.bookmark.rawValue && $0.cfi == locatorString
        }), let id = existing.id {
            await deleteAnnotation(id: id)
            return
        }

        _ = await createAnnotation(
            selectedText: "",
            locatorString: locatorString,
            chapterTitle: chapterTitle,
            type: .bookmark,
            color: .yellow,
            readerNote: nil
        )
    }

    private func save(_ note: BookNote) async -> BookNote? {
        do {
            let saved = try await noteDAO.save(note)
            await loadAnnotations()
            return saved
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.reader.annotation_save_failed"
            )
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
        return trimmedChapter.isEmpty
            ? AppLocalization.string("reader.bookmark")
            : trimmedChapter
    }
}
