import AppIntents

/// Registers App Shortcuts with Siri and the Shortcuts app.
struct PaperTokShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: [
                "Open a book in \(.applicationName)",
                "Read with \(.applicationName)",
            ],
            shortTitle: "Open Book",
            systemImageName: "book"
        )
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Chat with \(.applicationName)",
            ],
            shortTitle: "Ask AI",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "Send a message to \(.applicationName)",
                "Send images to \(.applicationName)",
            ],
            shortTitle: "Send Message",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: SearchBooksIntent(),
            phrases: [
                "Search books in \(.applicationName)",
                "Find a book in \(.applicationName)",
            ],
            shortTitle: "Search Books",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetReadingStatsIntent(),
            phrases: [
                "Get my reading stats from \(.applicationName)",
                "Show reading time in \(.applicationName)",
            ],
            shortTitle: "Reading Stats",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Add a book note to \(.applicationName)",
            ],
            shortTitle: "Create Note",
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
