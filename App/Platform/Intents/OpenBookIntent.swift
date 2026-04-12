import AppIntents
import PTCore

/// Siri Shortcut: "Open [Book Title] in PaperTok Reader"
struct OpenBookIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.open_book.title"
    static let description = IntentDescription("intent.open_book.description")
    static let openAppWhenRun = true

    @Parameter(title: "intent.open_book.parameter.book_title")
    var bookTitle: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLinkRouter.shared.route(to: .openBook(title: bookTitle))
        return .result(dialog: "Opening \"\(bookTitle)\"")
    }
}
