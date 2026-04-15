import Foundation

/// Normalized search hit used by the shared reader find bar UI.
///
/// Both the EPUB (`EPUBContentBridge`) and PDF (`PDFContentBridge`) backends
/// emit `ContentSearchResult` values; `ReaderSearchHit.from(_:)` maps those
/// into a format the SwiftUI find bar can navigate and decorate generically.
public struct ReaderSearchHit: Sendable, Equatable, Identifiable {
    public struct Locator: Sendable, Equatable {
        public var pageIndex: Int?
        public var cfi: String?
        public var range: NSRange?
        public var progression: Double

        public init(
            pageIndex: Int? = nil,
            cfi: String? = nil,
            range: NSRange? = nil,
            progression: Double = 0
        ) {
            self.pageIndex = pageIndex
            self.cfi = cfi
            self.range = range
            self.progression = progression
        }
    }

    public let id: UUID
    public let snippet: String
    public let contextBefore: String
    public let contextAfter: String
    public let chapterTitle: String
    public let locator: Locator

    public init(
        id: UUID = UUID(),
        snippet: String,
        contextBefore: String = "",
        contextAfter: String = "",
        chapterTitle: String = "",
        locator: Locator
    ) {
        self.id = id
        self.snippet = snippet
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.chapterTitle = chapterTitle
        self.locator = locator
    }
}

public extension ReaderSearchHit {
    /// Maps a generic `ContentSearchResult` to a `ReaderSearchHit`.
    ///
    /// For PDF results (`chapterHref` prefixed with `pages:`) the start page is
    /// extracted into `locator.pageIndex`. For EPUB results the `locatorString`
    /// (a Readium stored locator, typically containing a CFI) is placed into
    /// `locator.cfi`.
    static func from(_ result: ContentSearchResult) -> ReaderSearchHit {
        let snippet = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let locator = Locator(
            pageIndex: parsePageIndex(from: result.chapterHref),
            cfi: result.locatorString,
            range: nil,
            progression: result.progression
        )
        return ReaderSearchHit(
            snippet: snippet,
            contextBefore: result.textBefore,
            contextAfter: result.textAfter,
            chapterTitle: result.chapterTitle,
            locator: locator
        )
    }

    private static func parsePageIndex(from href: String) -> Int? {
        guard href.hasPrefix("pages:") else { return nil }
        let payload = href.dropFirst("pages:".count)
        let parts = payload.split(separator: "-", maxSplits: 1)
        guard let first = parts.first, let value = Int(first) else { return nil }
        return value
    }
}
