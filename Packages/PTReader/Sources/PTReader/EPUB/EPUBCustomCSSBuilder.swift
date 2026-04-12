import Foundation
#if canImport(PTCore)
import PTCore
#endif

/// Builds a CSS string that applies a `BookStyle` + `ReadTheme` combination to
/// Readium-rendered EPUB content.
///
/// The builder produces a single CSS block targeted at `html`, `body`, and
/// common block-level elements. It is intended to be fed into Readium's
/// Decoration system or a WebView JavaScript hook that injects the CSS into
/// the reader iframe.
public enum EPUBCustomCSSBuilder {

    public enum Mode: String, Sendable {
        case standard
        case night
        case sepia
        case highContrast
    }

    /// Builds a CSS string for the supplied style + theme.
    ///
    /// - Parameters:
    ///   - style: Book style (font, spacing, margins).
    ///   - theme: Color theme (background + text color).
    ///   - mode: Optional semantic override for night/sepia/high-contrast.
    public static func buildCSS(
        style: BookStyle,
        theme: ReadTheme,
        mode: Mode = .standard
    ) -> String {
        var lines: [String] = []

        let resolvedBackground: String
        let resolvedText: String
        switch mode {
        case .night:
            resolvedBackground = "#1A1A2E"
            resolvedText = "#E8E4E0"
        case .sepia:
            resolvedBackground = "#FAF4E8"
            resolvedText = "#121212"
        case .highContrast:
            resolvedBackground = "#000000"
            resolvedText = "#FFFFFF"
        case .standard:
            resolvedBackground = hexColor(theme.backgroundColor, fallback: "#FBFBF3")
            resolvedText = hexColor(theme.textColor, fallback: "#343434")
        }

        let fontSizePercent = Int((style.fontSize * 100).rounded())
        let lineHeight = formatDouble(style.lineHeight)
        let letterSpacing = formatDouble(style.letterSpacing)
        let wordSpacing = formatDouble(style.wordSpacing)
        let paragraphSpacing = formatDouble(style.paragraphSpacing)
        let fontFamily = cssFontFamily(style.fontFamily)

        lines.append("""
        html, body {
            background-color: \(resolvedBackground) !important;
            color: \(resolvedText) !important;
            font-family: \(fontFamily) !important;
            font-size: \(fontSizePercent)% !important;
            line-height: \(lineHeight) !important;
            letter-spacing: \(letterSpacing)em !important;
            word-spacing: \(wordSpacing)em !important;
            text-align: justify;
            padding-left: \(formatDouble(style.sideMargin))% !important;
            padding-right: \(formatDouble(style.sideMargin))% !important;
            padding-top: \(formatDouble(style.topMargin))px !important;
            padding-bottom: \(formatDouble(style.bottomMargin))px !important;
        }
        """)

        lines.append("""
        p {
            margin-top: \(paragraphSpacing)em !important;
            margin-bottom: \(paragraphSpacing)em !important;
            color: \(resolvedText) !important;
        }
        """)

        lines.append("""
        h1, h2, h3, h4, h5, h6 {
            color: \(resolvedText) !important;
            font-family: \(fontFamily) !important;
        }
        """)

        lines.append("""
        a, a:visited {
            color: \(resolvedText) !important;
            text-decoration: underline;
        }
        """)

        if mode == .highContrast {
            lines.append("""
            * {
                background-color: \(resolvedBackground) !important;
                color: \(resolvedText) !important;
                text-shadow: none !important;
            }
            """)
        }

        if mode == .night {
            lines.append("""
            img, svg {
                filter: brightness(.85) contrast(1.05);
            }
            """)
        }

        return lines.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    internal static func hexColor(_ raw: String, fallback: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        trimmed = trimmed.replacingOccurrences(of: "#", with: "")
        if trimmed.count == 8 {
            // AARRGGBB — drop alpha, return as #RRGGBB
            let rgb = String(trimmed.dropFirst(2))
            return "#\(rgb)"
        }
        if trimmed.count == 6 {
            return "#\(trimmed)"
        }
        return fallback
    }

    internal static func formatDouble(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    internal static func cssFontFamily(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "-apple-system, serif"
        }
        let quoted = trimmed.contains(" ") ? "\"\(trimmed)\"" : trimmed
        return "\(quoted), -apple-system, serif"
    }
}
