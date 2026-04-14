import AppIntents
import Foundation
import PTCore

/// Helper that opens the App Group database for use from App Intents.
///
/// Intents can fire in their own process while the host app is not
/// running, so they cannot rely on the in-memory `AppEnvironment`. This
/// helper mirrors the bootstrap logic in `PaperTokReaderApp` and is
/// safe to call from any intent's `perform()`.
enum IntentDatabaseAccess {
    static func open() throws -> AppDatabase {
        let containerURL = AppConfig.appGroupContainerURL()
        let dbDir = containerURL.appendingPathComponent("Database", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("paperreader.db").path
        return try AppDatabase.make(at: dbPath)
    }
}

/// Siri Shortcut: "Search books for [query] in PaperTok"
struct SearchBooksIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.search_books.title"
    static let description = IntentDescription(
        "intent.search_books.description"
    )
    static let openAppWhenRun = false

    @Parameter(title: "intent.parameter.query")
    var query: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .result(
                value: "",
                dialog: IntentDialog(stringLiteral: AppLocalization.string("intent.search_books.error.empty_query"))
            )
        }

        let database = try IntentDatabaseAccess.open()
        let dao = BookDAO(database: database)
        let books = try await dao.search(query: trimmed)

        if books.isEmpty {
            return .result(
                value: "",
                dialog: IntentDialog(stringLiteral: AppLocalization.format(
                    "intent.search_books.no_matches_format",
                    locale: .autoupdatingCurrent,
                    trimmed
                ))
            )
        }

        let lines = books.prefix(10).map { book -> String in
            let id = book.id.map(String.init) ?? "?"
            let author = book.author.isEmpty ? AppLocalization.string("common.unknown") : book.author
            return "\(book.title) — \(author) [#\(id)]"
        }
        let summary = lines.joined(separator: "\n")
        let count = books.count
        let dialog = IntentDialog(stringLiteral: AppLocalization.format(
            "intent.search_books.dialog.results_format",
            locale: .autoupdatingCurrent,
            count,
            trimmed
        ))
        return .result(value: summary, dialog: dialog)
    }
}
