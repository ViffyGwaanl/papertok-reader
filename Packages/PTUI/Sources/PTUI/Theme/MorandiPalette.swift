import SwiftUI

/// Morandi color palette — low-saturation earth tones for a premium reading experience.
public enum Morandi {
    // Core Palette
    public static let sage = Color(hex: "8FA68A")
    public static let dustyRose = Color(hex: "C4A4A0")
    public static let warmGray = Color(hex: "A8A098")
    public static let stone = Color(hex: "B8B0A8")
    public static let clay = Color(hex: "C0A890")
    public static let lavender = Color(hex: "B8A8C8")
    public static let powder = Color(hex: "A0B8C8")
    public static let sand = Color(hex: "D0C4B0")
    public static let mauve = Color(hex: "C8A0B0")
    public static let moss = Color(hex: "98A890")
    public static let taupe = Color(hex: "B0A498")
    public static let mist = Color(hex: "C8D0D0")

    // Semantic Colors
    public static let primaryText = Color(hex: "343434")
    public static let secondaryText = Color(hex: "8A8A8E")
    public static let tertiaryText = Color(hex: "B0B0B4")
    public static let background = Color(hex: "FAF8F5")
    public static let cardBackground = Color(hex: "FFFFFF")
    public static let accent = sage
    public static let divider = Color(hex: "E8E4E0")
    public static let destructive = Color(hex: "C87070")

    // Dark Mode
    public static let darkBackground = Color(hex: "1A1A2E")
    public static let darkCardBackground = Color(hex: "262640")
    public static let darkPrimaryText = Color(hex: "E8E4E0")
    public static let darkSecondaryText = Color(hex: "9090A0")

    // Highlight Colors (Morandi-tinted annotations)
    public static let highlightYellow = Color(hex: "E8D890")
    public static let highlightRed = Color(hex: "D09898")
    public static let highlightBlue = Color(hex: "90B0D0")
    public static let highlightGreen = Color(hex: "98C8A0")
    public static let highlightPurple = Color(hex: "B898C8")

    // Accent Presets
    public static let accentPresets: [(name: String, color: Color)] = [
        ("Sage", sage), ("Dusty Rose", dustyRose), ("Lavender", lavender),
        ("Powder Blue", powder), ("Clay", clay), ("Mauve", mauve),
        ("Moss", moss), ("Stone", stone),
    ]
}

extension Color {
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
}
