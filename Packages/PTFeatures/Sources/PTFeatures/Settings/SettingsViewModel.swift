import Foundation
import Observation
import PTCore

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
    public var aiProviderID: String {
        didSet {
            guard oldValue != aiProviderID else { return }
            aiModelID = Self.resolvedAIModelID(defaults: defaults, providerID: aiProviderID)
        }
    }
    public var aiModelID: String

    // Reading detail
    public var lineHeight: Double
    public var letterSpacing: Double
    public var paragraphSpacing: Double
    public var textIndent: Bool
    public var sideMargin: Double
    public var topMargin: Double
    public var bottomMargin: Double
    public var customCSS: String
    public var readingTheme: String

    // AI Tools
    public var enabledToolNames: Set<String>
    public var toolApprovalThreshold: String // "always" | "moderate" | "dangerous" | "never"

    // Quick Prompts (JSON-serialized)
    public var quickPromptsData: Data

    // Developer Options
    public var verboseLogging: Bool
    public var networkRequestLogging: Bool
    public var slowAnimations: Bool
    public var showDebugOverlay: Bool

    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = AppConfig.groupDefaults,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.defaults = defaults
        self.themeMode = defaults.string(forKey: "theme_mode") ?? AppConfig.Defaults.defaultThemeMode
        self.accentColorIndex = defaults.integer(forKey: "accent_color_index")
        self.isOLEDDarkMode = defaults.bool(forKey: "oled_dark_mode")
        self.defaultFontSize = defaults.double(forKey: "default_font_size").nonZero ?? AppConfig.Defaults.defaultFontSize
        self.pageTurnMode = defaults.string(forKey: "page_turn_mode") ?? AppConfig.Defaults.defaultPageTurnMode
        self.defaultFontFamily = defaults.string(forKey: "default_font_family")
            ?? BookStyle.preferredDefaultFontFamily(locale: locale)
        let initialProviderID = defaults.string(forKey: AppConfig.Keys.aiProviderID) ?? AppConfig.Defaults.defaultAIProviderID
        self.aiProviderID = initialProviderID
        self.aiModelID = Self.resolvedAIModelID(defaults: defaults, providerID: initialProviderID)

        self.lineHeight = defaults.double(forKey: "reading_line_height").nonZero ?? 1.4
        self.letterSpacing = defaults.double(forKey: "reading_letter_spacing")
        self.paragraphSpacing = defaults.double(forKey: "reading_paragraph_spacing").nonZero ?? 8.0
        self.textIndent = defaults.bool(forKey: "reading_text_indent")
        self.sideMargin = defaults.double(forKey: "reading_side_margin").nonZero ?? 16.0
        self.topMargin = defaults.double(forKey: "reading_top_margin").nonZero ?? 12.0
        self.bottomMargin = defaults.double(forKey: "reading_bottom_margin").nonZero ?? 12.0
        self.customCSS = defaults.string(forKey: "reading_custom_css") ?? ""
        self.readingTheme = defaults.string(forKey: "reading_theme") ?? "light"

        if let raw = defaults.stringArray(forKey: "ai_enabled_tools") {
            self.enabledToolNames = Set(raw)
        } else {
            self.enabledToolNames = []
        }
        self.toolApprovalThreshold = defaults.string(forKey: "ai_tool_approval_threshold") ?? "moderate"

        self.quickPromptsData = defaults.data(forKey: "ai_quick_prompts") ?? Data()

        self.verboseLogging = defaults.bool(forKey: "dev_verbose_logging")
        self.networkRequestLogging = defaults.bool(forKey: "dev_network_logging")
        self.slowAnimations = defaults.bool(forKey: "dev_slow_animations")
        self.showDebugOverlay = defaults.bool(forKey: "dev_debug_overlay")
    }

    public func save() {
        let previousProviderID = defaults.string(forKey: AppConfig.Keys.aiProviderID)
        let previousModelID = defaults.string(forKey: AppConfig.Keys.aiModelID)

        defaults.set(themeMode, forKey: "theme_mode")
        defaults.set(accentColorIndex, forKey: "accent_color_index")
        defaults.set(isOLEDDarkMode, forKey: "oled_dark_mode")
        defaults.set(defaultFontSize, forKey: "default_font_size")
        defaults.set(pageTurnMode, forKey: "page_turn_mode")
        defaults.set(defaultFontFamily, forKey: "default_font_family")
        defaults.set(aiProviderID, forKey: AppConfig.Keys.aiProviderID)
        defaults.set(aiModelID, forKey: AppConfig.Keys.aiModelID)
        if aiProviderID.isEmpty == false, aiModelID.isEmpty == false {
            defaults.set(aiModelID, forKey: "ai_model_for_\(aiProviderID)")
        }

        defaults.set(lineHeight, forKey: "reading_line_height")
        defaults.set(letterSpacing, forKey: "reading_letter_spacing")
        defaults.set(paragraphSpacing, forKey: "reading_paragraph_spacing")
        defaults.set(textIndent, forKey: "reading_text_indent")
        defaults.set(sideMargin, forKey: "reading_side_margin")
        defaults.set(topMargin, forKey: "reading_top_margin")
        defaults.set(bottomMargin, forKey: "reading_bottom_margin")
        defaults.set(customCSS, forKey: "reading_custom_css")
        defaults.set(readingTheme, forKey: "reading_theme")

        defaults.set(Array(enabledToolNames), forKey: "ai_enabled_tools")
        defaults.set(toolApprovalThreshold, forKey: "ai_tool_approval_threshold")
        defaults.set(quickPromptsData, forKey: "ai_quick_prompts")

        defaults.set(verboseLogging, forKey: "dev_verbose_logging")
        defaults.set(networkRequestLogging, forKey: "dev_network_logging")
        defaults.set(slowAnimations, forKey: "dev_slow_animations")
        defaults.set(showDebugOverlay, forKey: "dev_debug_overlay")

        if previousProviderID != aiProviderID || previousModelID != aiModelID {
            StoredAIProviderCatalog.postConfigurationDidChange()
        }
    }

    /// Load persisted QuickPrompts (or built-in defaults).
    public func loadQuickPrompts() -> [QuickPrompt] {
        if !quickPromptsData.isEmpty,
           let decoded = try? JSONDecoder().decode([QuickPrompt].self, from: quickPromptsData) {
            return decoded.sorted { $0.sortOrder < $1.sortOrder }
        }
        return QuickPrompt.builtIn
    }

    /// Persist QuickPrompts array.
    public func saveQuickPrompts(_ prompts: [QuickPrompt]) {
        if let data = try? JSONEncoder().encode(prompts) {
            quickPromptsData = data
            defaults.set(data, forKey: "ai_quick_prompts")
        }
    }

    /// Reset reading-detail values to defaults.
    public func resetReadingDetail() {
        defaultFontSize = AppConfig.Defaults.defaultFontSize
        defaultFontFamily = BookStyle.preferredDefaultFontFamily(locale: .autoupdatingCurrent)
        lineHeight = 1.4
        letterSpacing = 0
        paragraphSpacing = 8.0
        textIndent = false
        sideMargin = 16.0
        topMargin = 12.0
        bottomMargin = 12.0
        customCSS = ""
        readingTheme = "light"
        save()
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

    private static func resolvedAIModelID(defaults: UserDefaults, providerID: String) -> String {
        if let scopedModelID = normalized(defaults.string(forKey: "ai_model_for_\(providerID)")) {
            return scopedModelID
        }

        if normalized(defaults.string(forKey: AppConfig.Keys.aiProviderID)) == providerID,
           let globalModelID = normalized(defaults.string(forKey: AppConfig.Keys.aiModelID)) {
            return globalModelID
        }

        return AIProviderID(rawValue: providerID)?.defaultModel ?? AppConfig.Defaults.defaultOpenAIModelID
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
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
