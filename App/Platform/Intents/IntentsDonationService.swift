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
    }
}

/// Donates common actions to Siri for proactive suggestions.
enum IntentsDonationService {
    static func donateOpenBook(title: String) {
        let intent = OpenBookIntent()
        intent.bookTitle = title
    }

    static func donateAskAI(question: String) {
        let intent = AskAIIntent()
        intent.question = question
    }
}
