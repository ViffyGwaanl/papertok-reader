import AppIntents
import Foundation
import PTCore

enum CreateNoteIntentError: LocalizedError {
    case bookNotFound(String)

    var errorDescription: String? {
        switch self {
        case .bookNotFound(let title):
            return AppLocalization.format(
                "intent.create_note.error.book_not_found_format",
                locale: .autoupdatingCurrent,
                title
            )
        }
    }
}

/// Siri Shortcut: "Create a note for [book] in PaperTok"
struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.create_note.title"
    static let description = IntentDescription(
        "intent.create_note.description"
    )
    static let openAppWhenRun = false

    @Parameter(title: "intent.create_note.parameter.book_title")
    var bookTitle: String

    @Parameter(title: "intent.create_note.parameter.note_text")
    var noteText: String

    @Parameter(title: "intent.create_note.parameter.color")
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
        let summary = AppLocalization.format(
            "intent.create_note.summary_format",
            locale: .autoupdatingCurrent,
            savedId,
            book.title
        )
        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: AppLocalization.format(
                "intent.create_note.dialog_format",
                locale: .autoupdatingCurrent,
                book.title
            ))
        )
    }
}
