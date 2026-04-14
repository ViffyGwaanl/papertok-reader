import AppIntents

/// Registers App Shortcuts with Siri and the Shortcuts app.
struct PaperTokShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: [
                AppShortcutPhrase<OpenBookIntent>("Open a book in \(.applicationName)"),
                AppShortcutPhrase<OpenBookIntent>("Read with \(.applicationName)"),
            ],
            shortTitle: "intent.open_book.title",
            systemImageName: "book"
        )
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                AppShortcutPhrase<AskAIIntent>("Ask \(.applicationName) a question"),
                AppShortcutPhrase<AskAIIntent>("Chat with \(.applicationName)"),
            ],
            shortTitle: "intent.ask_ai.title",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                AppShortcutPhrase<SendMessageIntent>("Send a message to \(.applicationName)"),
                AppShortcutPhrase<SendMessageIntent>("Send images to \(.applicationName)"),
            ],
            shortTitle: "intent.send_message.title",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: SearchBooksIntent(),
            phrases: [
                AppShortcutPhrase<SearchBooksIntent>("Search books in \(.applicationName)"),
                AppShortcutPhrase<SearchBooksIntent>("Find a book in \(.applicationName)"),
            ],
            shortTitle: "intent.search_books.title",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetReadingStatsIntent(),
            phrases: [
                AppShortcutPhrase<GetReadingStatsIntent>("Get my reading stats from \(.applicationName)"),
                AppShortcutPhrase<GetReadingStatsIntent>("Show reading time in \(.applicationName)"),
            ],
            shortTitle: "intent.get_stats.title",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                AppShortcutPhrase<CreateNoteIntent>("Create a note in \(.applicationName)"),
                AppShortcutPhrase<CreateNoteIntent>("Add a book note to \(.applicationName)"),
            ],
            shortTitle: "intent.create_note.title",
            systemImageName: "note.text.badge.plus"
        )
    }
}

/// Donates common actions to Siri for proactive suggestions.
enum IntentsDonationService {
    @MainActor
    static func refreshShortcuts() {
        PaperTokShortcuts.updateAppShortcutParameters()
    }

    @MainActor
    static func donateOpenBook(title: String) async {
        var intent = OpenBookIntent()
        intent.bookTitle = title
        _ = try? await intent.donate()
    }

    @MainActor
    static func donateAskAI(question: String) async {
        var intent = AskAIIntent()
        intent.question = question
        _ = try? await intent.donate()
    }

    @MainActor
    static func donateSearchBooks(query: String) async {
        var intent = SearchBooksIntent()
        intent.query = query
        _ = try? await intent.donate()
    }

    @MainActor
    static func donateReadingStats(scope: ReadingStatsScope) async {
        var intent = GetReadingStatsIntent()
        intent.scope = scope
        _ = try? await intent.donate()
    }

    @MainActor
    static func donateCreateNote(bookTitle: String, noteText: String) async {
        var intent = CreateNoteIntent()
        intent.bookTitle = bookTitle
        intent.noteText = noteText
        _ = try? await intent.donate()
    }
}
