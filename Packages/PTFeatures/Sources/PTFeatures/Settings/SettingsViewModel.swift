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

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
        self.themeMode = defaults.string(forKey: "theme_mode") ?? AppConfig.Defaults.defaultThemeMode
        self.accentColorIndex = defaults.integer(forKey: "accent_color_index")
        self.isOLEDDarkMode = defaults.bool(forKey: "oled_dark_mode")
        self.defaultFontSize = defaults.double(forKey: "default_font_size").nonZero ?? AppConfig.Defaults.defaultFontSize
        self.pageTurnMode = defaults.string(forKey: "page_turn_mode") ?? AppConfig.Defaults.defaultPageTurnMode
    }

    public func save() {
        defaults.set(themeMode, forKey: "theme_mode")
        defaults.set(accentColorIndex, forKey: "accent_color_index")
        defaults.set(isOLEDDarkMode, forKey: "oled_dark_mode")
        defaults.set(defaultFontSize, forKey: "default_font_size")
        defaults.set(pageTurnMode, forKey: "page_turn_mode")
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
