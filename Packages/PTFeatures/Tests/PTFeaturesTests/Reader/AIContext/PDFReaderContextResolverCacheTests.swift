#if canImport(PDFKit) && canImport(UIKit)
import Testing
import Foundation
import PDFKit
import UIKit
import PTAIServices
import PTCore
import PTReader
@testable import PTFeatures

@Suite("PDFReaderContextResolver cache")
@MainActor
struct PDFReaderContextResolverCacheTests {
    private func makeDocument(pages: [String]) -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { ctx in
            for text in pages {
                ctx.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24)
                ]
                (text as NSString).draw(
                    at: CGPoint(x: 36, y: 36),
                    withAttributes: attrs
                )
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    private func makeBook() -> Book {
        var book = Book.placeholder(title: "Test Book", filePath: "/tmp/test.pdf")
        book.author = "Test Author"
        book.id = 7
        return book
    }

    @Test("Page scope misses cache on first access")
    func pageScopeMissesCacheOnFirstAccess() async throws {
        let doc = makeDocument(pages: ["Alpha unique", "Beta unique"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let cache = BookContentCache()
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 },
            cache: cache
        )
        let before = await cache.count()
        #expect(before == 0)
        _ = try await resolver.resolve(
            scope: .page,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        let after = await cache.count()
        #expect(after == 1)
        let key = BookContentCache.Key(bookId: "7", scope: .pdfPage(index: 0))
        let stored = await cache.get(key)
        #expect(stored?.contains("Alpha") == true)
    }

    @Test("Page scope hits cache on second access")
    func pageScopeHitsCacheOnSecondAccess() async throws {
        let doc = makeDocument(pages: ["Alpha unique", "Beta unique"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let cache = BookContentCache()
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 },
            cache: cache
        )
        _ = try await resolver.resolve(
            scope: .page,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        let key = BookContentCache.Key(bookId: "7", scope: .pdfPage(index: 0))
        await cache.set(key, value: "SENTINEL_PAGE_CACHE")
        let second = try await resolver.resolve(
            scope: .page,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        #expect(second.text == "SENTINEL_PAGE_CACHE")
    }

    @Test("Chapter scope uses cache")
    func chapterScopeUsesCache() async throws {
        let doc = makeDocument(pages: [
            "Chapter one page one",
            "Chapter one page two",
            "Chapter two page one",
        ])
        let outlineRoot = PDFOutline()
        let chOne = PDFOutline()
        chOne.label = "One"
        chOne.destination = PDFDestination(page: doc.page(at: 0)!, at: .zero)
        let chTwo = PDFOutline()
        chTwo.label = "Two"
        chTwo.destination = PDFDestination(page: doc.page(at: 2)!, at: .zero)
        outlineRoot.insertChild(chOne, at: 0)
        outlineRoot.insertChild(chTwo, at: 1)
        doc.outlineRoot = outlineRoot

        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let cache = BookContentCache()
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 },
            cache: cache
        )
        _ = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        // Chapter 1 spans pages 0 and 1.
        let key = BookContentCache.Key(
            bookId: "7",
            scope: .pdfChapter(startPage: 0, endPage: 1)
        )
        let stored = await cache.get(key)
        #expect(stored?.contains("Chapter one page one") == true)
        await cache.set(key, value: "SENTINEL_CHAPTER_CACHE")
        let second = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        #expect(second.text == "SENTINEL_CHAPTER_CACHE")
    }

    @Test("Whole book scope uses cache")
    func wholeBookScopeUsesCache() async throws {
        let doc = makeDocument(pages: ["First body", "Second body", "Third body"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let cache = BookContentCache()
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 },
            cache: cache
        )
        _ = try await resolver.resolve(
            scope: .wholeBook,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        let key = BookContentCache.Key(bookId: "7", scope: .pdfWholeBook)
        let stored = await cache.get(key)
        #expect(stored?.contains("First") == true)
        #expect(stored?.contains("Third") == true)
    }
}
#endif
