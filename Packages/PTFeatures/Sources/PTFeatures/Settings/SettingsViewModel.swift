import Foundation
import Observation

@MainActor @Observable
public final class SettingsViewModel {
    // Appearance
    public var themeMode: String
    public var accentColorIndex: Int
    public var isOLEDDarkMode: Bool

    // Reading
    public var defaultFontSize: Double
    public var pageTurnMode: String
    public var defaultFontFamily: String

    // AI Provider
    public var aiProviderID: String
    public var aiModelID: String

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
        self.themeMode = defaults.string(forKey: "theme_mode") ?? AppConfig.Defaults.defaultThemeMode
        self.accentColorIndex = defaults.integer(forKey: "accent_color_index")
        self.isOLEDDarkMode = defaults.bool(forKey: "oled_dark_mode")
        self.defaultFontSize = defaults.double(forKey: "default_font_size").nonZero ?? AppConfig.Defaults.defaultFontSize
        self.pageTurnMode = defaults.string(forKey: "page_turn_mode") ?? AppConfig.Defaults.defaultPageTurnMode
        self.defaultFontFamily = defaults.string(forKey: "default_font_family") ?? "System"
        self.aiProviderID = defaults.string(forKey: AppConfig.Keys.aiProviderID) ?? AppConfig.Defaults.defaultAIProviderID
        self.aiModelID = defaults.string(forKey: AppConfig.Keys.aiModelID) ?? AppConfig.Defaults.defaultOpenAIModelID
    }

    public func save() {
        defaults.set(themeMode, forKey: "theme_mode")
        defaults.set(accentColorIndex, forKey: "accent_color_index")
        defaults.set(isOLEDDarkMode, forKey: "oled_dark_mode")
        defaults.set(defaultFontSize, forKey: "default_font_size")
        defaults.set(pageTurnMode, forKey: "page_turn_mode")
        defaults.set(defaultFontFamily, forKey: "default_font_family")
        defaults.set(aiProviderID, forKey: AppConfig.Keys.aiProviderID)
        defaults.set(aiModelID, forKey: AppConfig.Keys.aiModelID)
    }

    // MARK: - AI Provider API Key Management

    /// Load the API key for a provider from Keychain.
    public nonisolated func loadAPIKey(for providerID: String) -> String {
        (try? KeychainService.load(key: "ai_api_key_\(providerID)")) ?? ""
    }

    /// Save the API key for a provider into Keychain.
    public nonisolated func saveAPIKey(_ key: String, for providerID: String) {
        if key.isEmpty {
            try? KeychainService.delete(key: "ai_api_key_\(providerID)")
        } else {
            try? KeychainService.save(key: "ai_api_key_\(providerID)", value: key)
        }
    }

    // MARK: - Data Management

    /// Calculate the size of cached/temporary files.
    public func cacheSize() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let size = directorySize(at: tempDir)
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Clear temporary caches.
    public func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) {
            for file in contents {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

/// Known AI provider identifiers for settings UI.
public enum AIProviderID: String, CaseIterable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case azure = "azure"
    case volcengine = "volcengine"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .azure: return "Azure OpenAI"
        case .volcengine: return "Volcengine (Doubao)"
        case .custom: return "Custom"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return AppConfig.Defaults.defaultOpenAIModelID
        case .anthropic: return AppConfig.Defaults.defaultAnthropicModelID
        case .gemini: return "gemini-2.0-flash-exp"
        case .azure: return ""
        case .volcengine: return "doubao-pro-32k"
        case .custom: return ""
        }
    }
}
