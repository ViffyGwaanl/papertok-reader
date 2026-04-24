import Foundation
import PTReader

/// Pure, testable policy that decides which `ChapterEntry` in a TOC list
/// should be rendered as "current" (i.e. matches the location the reader
/// is currently showing). Used by both the PDF TOC sheet and the EPUB
/// TOC sheet to draw a left-edge accent bar + subtle background highlight.
///
/// Matching rules:
/// - PDF hrefs follow `pages:<start>-<end>` and match when `currentPage`
///   is within `[start, end]`.
/// - EPUB hrefs match when they are the same href, or when the entry's
///   href is a prefix of the current locator href (so `chap1.xhtml` still
///   matches when the reader has scrolled to `chap1.xhtml#section-2`).
/// - An empty / nil current href (and no current page) means no highlight.
public struct TOCHighlightResolver: Sendable {
    public let entries: [ChapterEntry]
    public let currentHref: String?
    public let currentPage: Int?

    public init(entries: [ChapterEntry], currentHref: String?, currentPage: Int?) {
        self.entries = entries
        self.currentHref = currentHref
        self.currentPage = currentPage
    }

    /// Returns `true` when `entry` is the TOC row that should be rendered
    /// with the "current chapter" highlight.
    public func isCurrent(entry: ChapterEntry) -> Bool {
        if let page = currentPage, let range = Self.parsePdfPageRange(from: entry.href) {
            return page >= range.startPage && page <= range.endPage
        }
        guard let raw = currentHref?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return false
        }
        let currentNoFragment = Self.stripFragment(raw)
        let entryNoFragment = Self.stripFragment(entry.href)
        if currentNoFragment == entryNoFragment { return true }
        // Prefix match: current locator is "chap1.xhtml#section" -> we've
        // already stripped fragments above, so the remaining case is
        // `currentNoFragment` exactly equalling `entryNoFragment`. We keep
        // an explicit prefix-with-slash check as a defensive fallback for
        // packaged EPUBs that nest hrefs under directories.
        if currentNoFragment.hasSuffix(entryNoFragment) { return true }
        return false
    }

    private static func stripFragment(_ href: String) -> String {
        if let idx = href.firstIndex(of: "#") {
            return String(href[..<idx])
        }
        return href
    }

    private static func parsePdfPageRange(from href: String) -> (startPage: Int, endPage: Int)? {
        guard href.hasPrefix("pages:") else { return nil }
        let body = href.dropFirst("pages:".count)
        let parts = body.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        return (startPage: start, endPage: end)
    }
}
