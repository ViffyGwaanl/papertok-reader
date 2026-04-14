#if canImport(UIKit)
import Foundation
import UIKit
@preconcurrency import ReadiumNavigator
import PTCore

public struct EPUBReadingPreferencesSnapshot: Equatable, @unchecked Sendable {
    public let preferences: EPUBPreferences
    public let contentInsets: UIEdgeInsets

    public init(readingPreferences: ReadingPreferences) {
        let style = readingPreferences.style
        let theme = readingPreferences.theme

        preferences = EPUBPreferences(
            backgroundColor: Self.readiumColor(from: theme.backgroundColor),
            fontFamily: Self.fontFamily(from: style.fontFamily),
            fontSize: Self.clamp(style.fontSize, lower: 0.1, upper: 5.0),
            letterSpacing: Self.clamp(style.letterSpacing / 8.0, lower: 0, upper: 1.0),
            lineHeight: Self.clamp(style.lineHeight, lower: 1.0, upper: 2.0),
            pageMargins: Self.clamp(style.sideMargin / 6.0, lower: 0, upper: 4.0),
            paragraphSpacing: Self.clamp(style.paragraphSpacing / 2.0, lower: 0, upper: 2.0),
            publisherStyles: false,
            scroll: readingPreferences.isScrollMode || readingPreferences.pageTurnMode == .scroll,
            textAlign: Self.textAlignment(from: readingPreferences.textAlignment),
            textColor: Self.readiumColor(from: theme.textColor),
            theme: Self.theme(from: theme),
            wordSpacing: Self.clamp(style.wordSpacing, lower: 0, upper: 1.0)
        )

        contentInsets = UIEdgeInsets(
            top: CGFloat(max(style.topMargin, 0)),
            left: 0,
            bottom: CGFloat(max(style.bottomMargin, 0)),
            right: 0
        )
    }

    private static func fontFamily(from rawValue: String) -> FontFamily? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return FontFamily(rawValue: trimmed)
    }

    private static func readiumColor(from rawHex: String) -> ReadiumNavigator.Color? {
        let cleaned = rawHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.isEmpty == false else { return nil }
        return ReadiumNavigator.Color(hex: cleaned)
    }

    private static func textAlignment(from alignment: TextAlignment) -> ReadiumNavigator.TextAlignment {
        switch alignment {
        case .left:
            return .left
        case .right:
            return .right
        case .center:
            return .start
        case .justify:
            return .justify
        }
    }

    private static func theme(from theme: ReadTheme) -> Theme {
        let normalized = normalizeHex(theme.backgroundColor).uppercased()
        if normalized == normalizeHex(ReadTheme.defaultDark.backgroundColor).uppercased() || brightness(of: normalized) < 0.35 {
            return .dark
        }
        if normalized == normalizeHex(ReadTheme.defaultSepia.backgroundColor).uppercased() || isSepiaLike(normalized) {
            return .sepia
        }
        return .light
    }

    private static func normalizeHex(_ rawHex: String) -> String {
        let cleaned = rawHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        switch cleaned.count {
        case 8:
            return String(cleaned.suffix(6))
        case 6:
            return cleaned
        default:
            return ""
        }
    }

    private static func brightness(of normalizedHex: String) -> Double {
        guard normalizedHex.count == 6 else { return 1.0 }
        let red = Double(Int(normalizedHex.prefix(2), radix: 16) ?? 255)
        let green = Double(Int(normalizedHex.dropFirst(2).prefix(2), radix: 16) ?? 255)
        let blue = Double(Int(normalizedHex.suffix(2), radix: 16) ?? 255)
        return (0.299 * red + 0.587 * green + 0.114 * blue) / 255.0
    }

    private static func isSepiaLike(_ normalizedHex: String) -> Bool {
        guard normalizedHex.count == 6 else { return false }
        let red = Double(Int(normalizedHex.prefix(2), radix: 16) ?? 0)
        let green = Double(Int(normalizedHex.dropFirst(2).prefix(2), radix: 16) ?? 0)
        let blue = Double(Int(normalizedHex.suffix(2), radix: 16) ?? 0)
        return red > green && green > blue && brightness(of: normalizedHex) > 0.65
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
#endif
