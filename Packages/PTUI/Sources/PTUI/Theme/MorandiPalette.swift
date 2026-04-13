import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Morandi color palette — low-saturation earth tones for a premium reading experience.
///
/// All semantic colors are **adaptive**: they resolve to different values in light vs. dark mode
/// automatically based on the current `UITraitCollection` / `NSAppearance`. This gives every
/// surface, text style, accent, highlight, shadow, and status color polished dark-mode support
/// without callers needing to query `@Environment(\.colorScheme)`.
public enum Morandi {
    // MARK: - Core Palette (adaptive — brighter in dark mode for visibility on dark surfaces)
    public static let sage = Color(light: Color(hex: "8FA68A"), dark: Color(hex: "A8C2A2"))
    public static let dustyRose = Color(light: Color(hex: "C4A4A0"), dark: Color(hex: "D4B8AE"))
    public static let warmGray = Color(light: Color(hex: "A8A098"), dark: Color(hex: "9A9690"))
    public static let stone = Color(light: Color(hex: "B8B0A8"), dark: Color(hex: "A0988F"))
    public static let clay = Color(light: Color(hex: "C0A890"), dark: Color(hex: "DDB992"))
    public static let lavender = Color(light: Color(hex: "B8A8C8"), dark: Color(hex: "B3ACCA"))
    public static let powder = Color(light: Color(hex: "A0B8C8"), dark: Color(hex: "BAC9D7"))
    public static let sand = Color(light: Color(hex: "D0C4B0"), dark: Color(hex: "4A4A5A"))
    public static let mauve = Color(light: Color(hex: "C8A0B0"), dark: Color(hex: "D0ACBA"))
    public static let moss = Color(light: Color(hex: "98A890"), dark: Color(hex: "98A586"))
    public static let taupe = Color(light: Color(hex: "B0A498"), dark: Color(hex: "9A8F82"))
    public static let mist = Color(light: Color(hex: "C8D0D0"), dark: Color(hex: "6C7A82"))

    // MARK: - Surfaces (adaptive)
    public static let background = Color(light: Color(hex: "FAF8F5"), dark: Color(hex: "1A1A2E"))
    public static let cardBackground = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "2C2C3F"))
    public static let elevatedBackground = Color(light: Color(hex: "F2EEE8"), dark: Color(hex: "252538"))

    // MARK: - Text (adaptive)
    public static let primaryText = Color(light: Color(hex: "343434"), dark: Color(hex: "F0EDE5"))
    public static let secondaryText = Color(light: Color(hex: "8A8A8E"), dark: Color(hex: "A8A8B8"))
    public static let tertiaryText = Color(light: Color(hex: "B0B0B4"), dark: Color(hex: "70707E"))

    // MARK: - Accent & Dividers
    public static let accent = sage
    public static let divider = Color(light: Color(hex: "E8E4E0"), dark: Color(hex: "3A3A52"))

    // MARK: - Status colors (adaptive)
    public static let success = Color(light: Color(hex: "7FA88A"), dark: Color(hex: "96C2A2"))
    public static let warning = Color(light: Color(hex: "D4A574"), dark: Color(hex: "E0BC8F"))
    public static let error = Color(light: Color(hex: "C47A7A"), dark: Color(hex: "D89898"))
    public static let info = Color(light: Color(hex: "7A9CB8"), dark: Color(hex: "94B0C9"))
    public static let destructive = Color(light: Color(hex: "C87070"), dark: Color(hex: "D89090"))

    // MARK: - Highlight Colors (adaptive — annotations readable in both modes)
    public static let highlightYellow = Color(light: Color(hex: "E8D890"), dark: Color(hex: "B3A657"))
    public static let highlightPink = Color(light: Color(hex: "F5B8C0"), dark: Color(hex: "B37782"))
    public static let highlightRed = Color(light: Color(hex: "D09898"), dark: Color(hex: "B37272"))
    public static let highlightBlue = Color(light: Color(hex: "90B0D0"), dark: Color(hex: "6B8BA8"))
    public static let highlightGreen = Color(light: Color(hex: "98C8A0"), dark: Color(hex: "7A9C72"))
    public static let highlightPurple = Color(light: Color(hex: "B898C8"), dark: Color(hex: "8970A3"))

    // MARK: - Shadows (adaptive — stronger in dark mode for visible elevation)
    public static let shadow = Color(light: Color.black.opacity(0.08), dark: Color.black.opacity(0.3))
    public static let shadowStrong = Color(light: Color.black.opacity(0.15), dark: Color.black.opacity(0.5))

    // MARK: - Backward-compat dark aliases
    // The semantic colors above are already adaptive, so the following aliases simply map to
    // the dark-mode values for any lingering call sites.
    public static let darkBackground = Color(hex: "1A1A2E")
    public static let darkCardBackground = Color(hex: "2C2C3F")
    public static let darkPrimaryText = Color(hex: "F0EDE5")
    public static let darkSecondaryText = Color(hex: "A8A8B8")

    // MARK: - Accent Presets
    public static let accentPresets: [(name: String, color: Color)] = [
        ("Sage", sage), ("Dusty Rose", dustyRose), ("Lavender", lavender),
        ("Powder Blue", powder), ("Clay", clay), ("Mauve", mauve),
        ("Moss", moss), ("Stone", stone),
    ]
}

// MARK: - Color extensions

extension Color {
    /// Hex string initializer — supports "RRGGBB" and "AARRGGBB".
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: Double
        switch hex.count {
        case 6:
            (r, g, b, a) = (Double((int >> 16) & 0xFF) / 255, Double((int >> 8) & 0xFF) / 255, Double(int & 0xFF) / 255, 1.0)
        case 8:
            (a, r, g, b) = (Double((int >> 24) & 0xFF) / 255, Double((int >> 16) & 0xFF) / 255, Double((int >> 8) & 0xFF) / 255, Double(int & 0xFF) / 255)
        default:
            (r, g, b, a) = (0, 0, 0, 1)
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Builds an adaptive color that resolves to `light` in light mode and `dark` in dark mode.
    public init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }
}
