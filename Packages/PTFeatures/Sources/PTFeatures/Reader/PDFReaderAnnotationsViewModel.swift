import Foundation
import Observation
import PTCore
import PTReader

#if canImport(PDFKit)
import PDFKit

@MainActor @Observable
public final class PDFReaderAnnotationsViewModel {
    public let bookId: Int64
    public private(set) var notes: [BookNote] = []
    public private(set) var renderedAnnotations: [PDFRenderedAnnotation] = []
    public private(set) var errorMessage: String?

    private let noteDAO: BookNoteDAO
    private let document: PDFDocument

    public init(bookId: Int64, database: AppDatabase, document: PDFDocument) {
        self.bookId = bookId
        self.noteDAO = BookNoteDAO(database: database)
        self.document = document
    }

    public func loadAnnotations() async {
        do {
            notes = try await noteDAO.fetchByBookId(bookId)
            renderedAnnotations = notes.flatMap { PDFAnnotationBridge.renderedAnnotations(from: $0, in: document) }
            errorMessage = nil
        } catch {
            notes = []
            renderedAnnotations = []
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
            renderedAnnotations = notes.flatMap { PDFAnnotationBridge.renderedAnnotations(from: $0, in: document) }
            errorMessage = nil
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.reader.annotation_delete_failed"
            )
        }
    }

    public func annotationDraft(noteID: Int64) -> EPUBReaderAnnotationDraft? {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            return nil
        }
        return EPUBReaderAnnotationDraft(note: note)
    }

    /// Routes a PDF annotation tap (from PDFKit's annotation hit-testing) to
    /// the shared context-menu coordinator so the reader can surface the
    /// existing-annotation edit sheet.
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
#endif
