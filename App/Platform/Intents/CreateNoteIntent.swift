import AppIntents
import Foundation
import PTCore

enum CreateNoteIntentError: LocalizedError {
    case bookNotFound(String)

    var errorDescription: String? {
        switch self {
        case .bookNotFound(let title):
            return "No book in your PaperTok library matched \"\(title)\"."
        }
    }
}

/// Siri Shortcut: "Create a note for [book] in PaperTok"
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription(
        "Captures a free-form note attached to a book in your PaperTok library."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Book Title")
    var bookTitle: String

    @Parameter(title: "Note")
    var noteText: String

    @Parameter(title: "Color (optional)")
    var color: String?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let title = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = noteText.trimmingCharacters(in: .whitespacesAndNewlines)

        let database = try IntentDatabaseAccess.open()
        let bookDAO = BookDAO(database: database)
        let matches = try await bookDAO.search(query: title)
        guard let book = matches.first, let bookId = book.id else {
            throw CreateNoteIntentError.bookNotFound(title)
        }

        let note = BookNote(
            bookId: bookId,
            content: body,
            type: "note",
            color: color ?? "",
            createTime: Date(),
            updateTime: Date()
        )

        let saved = try await BookNoteDAO(database: database).save(note)
        let savedId = saved.id.map(String.init) ?? "?"
        let summary = "Added note #\(savedId) to \"\(book.title)\"."
        return .result(value: summary, dialog: "Saved note to \(book.title).")
    }
}
