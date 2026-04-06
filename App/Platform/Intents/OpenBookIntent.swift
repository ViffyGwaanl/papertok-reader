import AppIntents
import PTCore

/// Siri Shortcut: "Open [Book Title] in PaperTok Reader"
struct OpenBookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Book"
    static let description = IntentDescription("Open a specific book in PaperTok Reader")

    @Parameter(title: "Book Title")
    var bookTitle: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLinkRouter.shared.route(to: .openBook(title: bookTitle))
        return .result(dialog: "Opening \"\(bookTitle)\"")
    }
}
