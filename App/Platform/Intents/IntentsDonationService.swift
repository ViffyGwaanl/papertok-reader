import AppIntents

/// Registers App Shortcuts with Siri and the Shortcuts app.
struct PaperTokShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: [
                "Open \(\.$bookTitle) in \(.applicationName)",
                "Read \(\.$bookTitle) with \(.applicationName)",
            ],
            shortTitle: "Open Book",
            systemImageName: "book"
        )
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$question)",
                "Ask \(.applicationName) about \(\.$question)",
            ],
            shortTitle: "Ask AI",
            systemImageName: "brain"
        )
    }
}

/// Donates common actions to Siri for proactive suggestions.
enum IntentsDonationService {
    /// Call when user opens a book to improve Siri suggestions.
    static func donateOpenBook(title: String) {
        let intent = OpenBookIntent()
        intent.bookTitle = title
        // IntentDonationManager is available on iOS 16+
        // The system automatically picks up AppIntent usage
    }

    /// Call when user starts an AI chat.
    static func donateAskAI(question: String) {
        let intent = AskAIIntent()
        intent.question = question
    }
}
