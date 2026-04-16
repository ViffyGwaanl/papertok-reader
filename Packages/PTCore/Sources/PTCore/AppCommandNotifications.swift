import Foundation

public extension Notification.Name {
    static let importBook = Notification.Name("PaperTokImportBook")
    static let toggleAIPanel = Notification.Name("PaperTokToggleAI")
    static let previousChapter = Notification.Name("PaperTokPreviousChapter")
    static let nextChapter = Notification.Name("PaperTokNextChapter")
    static let increaseFontSize = Notification.Name("PaperTokIncreaseFontSize")
    static let decreaseFontSize = Notification.Name("PaperTokDecreaseFontSize")
    static let showInFinder = Notification.Name("PaperTokShowInFinder")
    /// Posted when the user taps the read-only provider chip in the AI chat
    /// composer. The ContentView translates this into a navigation to
    /// Settings → AI Provider Center (W5.3 consolidation — the in-chat picker
    /// is retired; provider/model selection lives in Settings only).
    static let openAIProviderSettings = Notification.Name("PaperTokOpenAIProviderSettings")
}
