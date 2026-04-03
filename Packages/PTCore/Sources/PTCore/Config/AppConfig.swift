import Foundation

public enum AppConfig {
    public static let suiteName = "group.ai.papertok.paperreader"
    public static let bundleId = "ai.papertok.paperreader"
    public static let urlScheme = "paperreader"

    public static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public enum Defaults {
        public static let defaultFontSize: Double = 18.0
        public static let defaultPageTurnMode = "swipe"
        public static let defaultThemeMode = "system"
        public static let maxAttachmentImages = 4
        public static let maxAttachmentTextFiles = 3
        public static let maxPromptLength = 20_000
    }
}
