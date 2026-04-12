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
}
