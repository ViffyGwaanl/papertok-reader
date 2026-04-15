import Foundation
import SwiftUI
import PTUI

/// Standalone helper for recognizing inline `[N]` citation markers in assistant
/// message bodies and decorating them with superscript styling.
///
/// This ships as an independent helper because the existing Markdown block parser
/// is a file-scope enum inside `MessageBubbleView.swift` which the W2.2c parallel
/// session owns. W2.2c can adopt this renderer when wiring `CitationsFooterView`
/// into the message bubble.
enum CitationMarkdownRenderer {

    struct Marker: Equatable {
        let index: Int
        let range: Range<String.Index>
    }

    private static let pattern: NSRegularExpression = {
        // Matches `[N]` where N is 1-3 digits. Captures the digits.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: "\\[(\\d{1,3})\\]")
    }()

    /// Scans the input for `[N]` markers where N is a 1-3 digit integer and
    /// returns them in order of appearance.
    static func markers(in text: String) -> [Marker] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var results: [Marker] = []
        pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let digitsNSRange = match.range(at: 1)
            guard digitsNSRange.location != NSNotFound else { return }
            let digits = ns.substring(with: digitsNSRange)
            guard let value = Int(digits) else { return }
            guard let swiftRange = Range(match.range, in: text) else { return }
            results.append(Marker(index: value, range: swiftRange))
        }
        return results
    }

    /// Renders `text` as an `AttributedString` where every `[N]` marker is
    /// styled with a raised baseline and smaller caption font in accent color.
    static func render(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for marker in markers(in: text) {
            let nsRange = NSRange(marker.range, in: text)
            guard let attrRange = Range(nsRange, in: attributed) else { continue }
            attributed[attrRange].baselineOffset = 4
            attributed[attrRange].font = .caption2.weight(.semibold)
            attributed[attrRange].foregroundColor = Morandi.accent
        }
        return attributed
    }
}
