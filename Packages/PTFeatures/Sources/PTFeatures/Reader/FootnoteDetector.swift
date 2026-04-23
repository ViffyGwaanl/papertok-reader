import Foundation

/// Heuristic detector for EPUB footnote targets.
///
/// Many EPUB publishers mark footnote anchors with hrefs that contain a
/// fragment whose identifier starts with `fn`, `footnote`, `note` or
/// `fnref`. Relying on the fragment alone is best-effort — the richer
/// signal would be a `role="doc-footnote"` or `epub:type="footnote"`
/// attribute on the target element — but the fragment-based heuristic
/// already covers the popular layouts shipped by Project Gutenberg,
/// Standard Ebooks, O'Reilly and academic presses. Callers that care
/// about a strict signal can combine this with an inline
/// `epub:type` probe from Readium's content bridge.
public enum FootnoteDetector {
    private static let fragmentPatterns: [String] = [
        "fn-",
        "fn_",
        "fnref-",
        "fnref_",
        "footnote-",
        "footnote_",
        "note",
    ]

    public static func isFootnote(href: String) -> Bool {
        guard href.isEmpty == false else { return false }
        guard let hashIndex = href.firstIndex(of: "#") else { return false }
        let fragment = href[href.index(after: hashIndex)...]
        guard fragment.isEmpty == false else { return false }
        let lowered = fragment.lowercased()
        return fragmentPatterns.contains { lowered.hasPrefix($0) }
    }
}
