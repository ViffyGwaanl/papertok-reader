import Foundation
import Observation
import PTCore
import PTReader
import PTAIServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Coordinates the reader context menu lifecycle: tracks selected text,
/// manages active sheet state, and integrates with persistence and AI services.
@Observable
public final class ContextMenuCoordinator {

    // MARK: - Selection State

    /// The text the user has selected.
    public var selectedText: String = ""

    /// A locator string for the selected text (e.g. PDF anchor or EPUB CFI).
    public var selectedLocator: String = ""

    /// The chapter title where the selection was made.
    public var chapterTitle: String = ""

    /// Whether the floating context menu is visible.
    public var isMenuVisible: Bool = false

    /// The highlight color for the next highlight action.
    public var highlightColor: HighlightColor = .yellow

    // MARK: - Active Sheet

    /// Which secondary sheet is currently presented (if any).
    public var activeSheet: ActiveSheet?

    public enum ActiveSheet: Identifiable, Equatable {
        case translation
        case excerpt
        case note
        case noteEdit(noteID: Int64)
        case dictionary

        public var id: String {
            switch self {
            case .translation: return "translation"
            case .excerpt: return "excerpt"
            case .note: return "note"
            case .noteEdit(let id): return "noteEdit-\(id)"
            case .dictionary: return "dictionary"
            }
        }
    }

    // MARK: - Dependencies

    private let bookId: Int64
    private let bookTitle: String
    private let bookAuthor: String
    private let noteDAO: BookNoteDAO
    public let translationService: AITranslationService?
    private let onSendToAI: ((String) async -> Void)?

    // MARK: - Init

    public init(
        bookId: Int64,
        bookTitle: String,
        bookAuthor: String,
        database: AppDatabase,
        translationService: AITranslationService? = nil,
        onSendToAI: ((String) async -> Void)? = nil
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.noteDAO = BookNoteDAO(database: database)
        self.translationService = translationService
        self.onSendToAI = onSendToAI
    }

    // MARK: - Public API

    /// Show the context menu for the given selection.
    public func showMenu(text: String, locator: String, chapter: String) {
        selectedText = text
        selectedLocator = locator
        chapterTitle = chapter
        isMenuVisible = true
        activeSheet = nil
    }

    /// Dismiss the context menu and any active sheet.
    public func dismiss() {
        isMenuVisible = false
        activeSheet = nil
        selectedText = ""
        selectedLocator = ""
        chapterTitle = ""
    }

    /// Handle a context menu action tap.
    public func handleAction(_ action: ContextMenuAction) {
        switch action {
        case .highlight:
            Task { await createHighlight() }

        case .note:
            activeSheet = .note
            isMenuVisible = false

        case .copy:
            copySelectedText()
            dismiss()

        case .translate:
            activeSheet = .translation
            isMenuVisible = false

        case .explain:
            sendToAI(prompt: explainPrompt)

        case .summarize:
            sendToAI(prompt: summarizePrompt)

        case .define:
            // Show the system dictionary instead of asking the LLM. The
            // dictionary lookup runs entirely on-device.
            activeSheet = .dictionary
            isMenuVisible = false

        case .search:
            // Search is handled by the reader view model directly;
            // post a notification so the reader can open its search sheet.
            NotificationCenter.default.post(
                name: .contextMenuSearchRequested,
                object: nil,
                userInfo: ["query": selectedText]
            )
            dismiss()

        case .share:
            activeSheet = .excerpt
            isMenuVisible = false
        }
    }

    // MARK: - Note Persistence

    /// Create a highlight-only BookNote for the current selection.
    public func createHighlight() async {
        let note = BookNote(
            bookId: bookId,
            content: selectedText,
            cfi: selectedLocator,
            chapter: chapterTitle,
            type: NoteType.highlight.rawValue,
            color: highlightColor.hex,
            createTime: Date(),
            updateTime: Date()
        )
        _ = try? await noteDAO.save(note)
        await MainActor.run { dismiss() }
    }

    /// Create or update a note annotation.
    public func saveNote(color: HighlightColor, noteText: String, existingID: Int64? = nil) async {
        if let existingID {
            // Fetch existing, update fields
            if let existing = try? await noteDAO.fetchByBookId(bookId).first(where: { $0.id == existingID }) {
                var updated = existing
                updated.color = color.hex
                updated.readerNote = noteText
                updated.updateTime = Date()
                _ = try? await noteDAO.save(updated)
            }
        } else {
            let note = BookNote(
                bookId: bookId,
                content: selectedText,
                cfi: selectedLocator,
                chapter: chapterTitle,
                type: NoteType.note.rawValue,
                color: color.hex,
                readerNote: noteText,
                createTime: Date(),
                updateTime: Date()
            )
            _ = try? await noteDAO.save(note)
        }
        await MainActor.run {
            activeSheet = nil
            dismiss()
        }
    }

    /// Delete an existing annotation.
    public func deleteNote(id: Int64) async {
        try? await noteDAO.delete(id: id)
        await MainActor.run {
            activeSheet = nil
            dismiss()
        }
    }

    /// Save selected text as a notes-type BookNote (from excerpt sheet).
    public func saveExcerptToNotes() async {
        let note = BookNote(
            bookId: bookId,
            content: selectedText,
            cfi: selectedLocator,
            chapter: chapterTitle,
            type: NoteType.highlight.rawValue,
            color: highlightColor.hex,
            createTime: Date(),
            updateTime: Date()
        )
        _ = try? await noteDAO.save(note)
        await MainActor.run { activeSheet = nil }
    }

    // MARK: - Private Helpers

    private func copySelectedText() {
        #if os(iOS)
        UIPasteboard.general.string = selectedText
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
        #endif
    }

    private func sendToAI(prompt: String) {
        let callback = onSendToAI
        isMenuVisible = false
        activeSheet = nil
        Task {
            await callback?(prompt)
        }
    }

    private var contextLine: String {
        chapterTitle.isEmpty
            ? "from \"\(bookTitle)\""
            : "from \"\(bookTitle)\", chapter \"\(chapterTitle)\""
    }

    private var explainPrompt: String {
        "Please explain the following passage \(contextLine):\n\n\"\(selectedText)\""
    }

    private var summarizePrompt: String {
        "Please summarize the key points of this passage \(contextLine):\n\n\"\(selectedText)\""
    }

}

// MARK: - Notification Name

public extension Notification.Name {
    static let contextMenuSearchRequested = Notification.Name("PTContextMenuSearchRequested")
}
