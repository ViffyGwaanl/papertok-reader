import Foundation

/// A chapter within a PDF, defined by a page range.
public struct PDFChapter: Sendable, Equatable {
    public let title: String
    public let startPage: Int
    public let endPage: Int
    public let level: Int

    public init(title: String, startPage: Int, endPage: Int, level: Int = 0) {
        self.title = title
        self.startPage = startPage
        self.endPage = endPage
        self.level = level
    }

    public var pageCount: Int {
        endPage - startPage + 1
    }

    public var href: String {
        "pages:\(startPage)-\(endPage)"
    }

    public func toChapterEntry() -> ChapterEntry {
        ChapterEntry(title: title, href: href, level: level)
    }

    public static func parsePageRange(from href: String) -> (startPage: Int, endPage: Int)? {
        guard href.hasPrefix("pages:") else { return nil }
        let range = href.dropFirst("pages:".count)
        let parts = range.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else { return nil }
        return (start, end)
    }
}
