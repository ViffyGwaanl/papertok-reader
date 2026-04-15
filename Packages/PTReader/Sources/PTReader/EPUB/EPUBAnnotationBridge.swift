#if canImport(ReadiumShared) && canImport(ReadiumNavigator)
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import ReadiumNavigator
import ReadiumShared
import PTCore

/// Converts PTCore BookNote annotations to/from Readium Decoration decorations.
///
/// This bridge handles the mapping between the app's annotation model (BookNote)
/// and Readium's rendering model (Decoration) for highlights and underlines.
public enum EPUBAnnotationBridge {

    /// Intermediate style representation for BookNote -> Decoration mapping.
    public struct DecoratorStyle: Sendable {
        public let tint: String
        public let style: String // "highlight" | "underline" | "strikethrough"

        public init(tint: String, style: String = "highlight") {
            self.tint = tint
            self.style = style
        }
    }

    /// Map a BookNote to a DecoratorStyle.
    public static func decoratorStyle(for note: BookNote) -> DecoratorStyle {
        let noteType = NoteType(rawValue: note.type)
        let styleString: String
        switch noteType {
        case .bookmark:
            styleString = "underline"
        case .underline:
            styleString = "underline"
        case .strikethrough:
            styleString = "strikethrough"
        default:
            styleString = "highlight"
        }
        return DecoratorStyle(
            tint: note.color.isEmpty ? HighlightColor.yellow.hex : note.color,
            style: styleString
        )
    }

    /// Build a Readium Decoration from a BookNote.
    ///
    /// The BookNote's `cfi` field is stored as a JSON-encoded Locator string.
    /// Returns nil if the locator cannot be parsed.
    public static func decoration(from note: BookNote) -> Decoration? {
        guard let locator = locator(fromStoredString: note.cfi) else {
            return nil
        }
        let style = decoratorStyle(for: note)
        let tintColor = colorFromHex(style.tint)

        let decorationStyle: Decoration.Style
        switch style.style {
        case "underline":
            decorationStyle = .underline(tint: tintColor)
        case "strikethrough":
            // Readium 3.8.0 ships no built-in .strikethrough style.
            // Render as an underline-tinted decoration to visually distinguish
            // the annotation from a highlight while we live on 3.8.0. The
            // persisted BookNote still carries the correct kind, so a future
            // custom HTMLDecorationTemplate can upgrade the rendering.
            decorationStyle = .underline(tint: tintColor)
        default:
            decorationStyle = .highlight(tint: tintColor)
        }

        return Decoration(
            id: note.id.map { "\($0)" } ?? UUID().uuidString,
            locator: locator,
            style: decorationStyle
        )
    }

    /// Build a BookNote from a Readium Locator and selected text.
    ///
    /// The locator is serialized to JSON for storage in the `cfi` field.
    public static func bookNote(
        bookId: Int64,
        locator: Locator,
        selectedText: String,
        chapter: String,
        color: String = "",
        type: NoteType = .highlight,
        readerNote: String? = nil
    ) -> BookNote {
        let cfi = storedString(from: locator)
        let timestamp = Date()
        return BookNote(
            bookId: bookId,
            content: selectedText,
            cfi: cfi,
            chapter: chapter,
            type: type.rawValue,
            color: color.isEmpty ? HighlightColor.yellow.hex : color,
            readerNote: readerNote,
            createTime: timestamp,
            updateTime: timestamp
        )
    }

    /// Convert a stored locator string back to a Readium Locator.
    public static func locator(fromStoredString stored: String) -> Locator? {
        guard !stored.isEmpty else { return nil }
        return try? Locator(jsonString: stored)
    }

    /// Serialize a Readium Locator to a JSON string for storage.
    public static func storedString(from locator: Locator) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: locator.json, options: []),
              let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    // MARK: - Private

    #if canImport(UIKit)
    private static func colorFromHex(_ hex: String) -> UIColor? {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 || clean.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgbValue)
        if clean.count == 8 {
            return UIColor(
                red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgbValue & 0xFF) / 255.0,
                alpha: CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            )
        }
        return UIColor(
            red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgbValue & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
    #elseif canImport(AppKit)
    private static func colorFromHex(_ hex: String) -> NSColor? {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 || clean.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgbValue)
        if clean.count == 8 {
            return NSColor(
                red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgbValue & 0xFF) / 255.0,
                alpha: CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            )
        }
        return NSColor(
            red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgbValue & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
    #endif
}
#endif
