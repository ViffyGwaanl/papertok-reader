import Foundation

public enum AppConfig {
    public static let suiteName = "group.ai.papertok.paperreader"
    public static let bundleId = "ai.papertok.paperreader"
    public static let urlScheme = "paperreader"

    public enum Keys {
        public static let aiProviderID = "ai_provider_id"
        public static let aiModelID = "ai_model_id"
        public static let aiSystemPrompt = "ai_system_prompt"
        public static let aiThinkingLevel = "ai_thinking_level"
        public static let shareDefaultRoute = "share_default_route"
        public static let themeMode = "theme_mode"
        public static let accentColorIndex = "accent_color_index"
        public static let oledDarkMode = "oled_dark_mode"
        public static let defaultFontSize = "default_font_size"
        public static let pageTurnMode = "page_turn_mode"
    }

    public static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static func appGroupContainerURL(fileManager: FileManager = .default) -> URL {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func documentsURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public enum Defaults {
        public static let defaultFontSize: Double = 18.0
        public static let defaultPageTurnMode = "swipe"
        public static let defaultThemeMode = "system"
        public static let maxAttachmentImages = 4
        public static let maxAttachmentTextFiles = 3
        public static let maxPromptLength = 20_000
        public static let defaultAIProviderID = "openai"
        public static let defaultOpenAIModelID = "gpt-4o"
        public static let defaultAnthropicModelID = "claude-sonnet-4-20250514"
        public static let defaultShareDefaultRoute = "auto"
        public static let defaultTTSBackend = "system"
        public static let syncConflictStrategy = "lastModifiedWins"
        public static let ragEmbeddingEndpoint = ""
        public static let mcpTransportType = "http"
    }
}
