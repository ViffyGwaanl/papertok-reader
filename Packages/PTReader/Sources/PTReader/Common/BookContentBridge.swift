import Foundation

/// Unified content access protocol for both EPUB and PDF books.
///
/// This protocol enables AI tools to access book content regardless of format.
/// EPUB implementation uses Readium Publication APIs.
/// PDF implementation uses PDFKit + Vision OCR.
public protocol BookContentBridge: Sendable {
    /// The book's title.
    var title: String { get }

    /// The book's table of contents as chapter entries.
    var tableOfContents: [ChapterEntry] { get async throws }

    /// Extract text content of a specific chapter.
    /// - Parameter href: Chapter identifier (EPUB href or PDF page range like "pages:10-20").
    func extractChapterContent(href: String) async throws -> String

    /// Extract the full text of the entire book.
    func extractFullText() async throws -> String

    /// Search for a query string within the book's content.
    func searchContent(query: String) async throws -> [ContentSearchResult]
}

/// A chapter/section entry in the table of contents.
public struct ChapterEntry: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let title: String
    public let href: String
    /// Nesting level (0 = top-level chapter).
    public let level: Int
    /// Number of child entries (for expandable TOC UI).
    public let childCount: Int

    public init(title: String, href: String, level: Int = 0, childCount: Int = 0) {
        self.title = title
        self.href = href
        self.level = level
        self.childCount = childCount
    }
}
