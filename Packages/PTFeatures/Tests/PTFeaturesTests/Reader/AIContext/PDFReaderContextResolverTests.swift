#if canImport(PDFKit) && canImport(UIKit)
import Testing
import Foundation
import PDFKit
import UIKit
import PTCore
import PTReader
@testable import PTFeatures

@Suite("PDFReaderContextResolver")
@MainActor
struct PDFReaderContextResolverTests {
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
        return book
    }

    @Test("Selection scope returns supplied selection")
    func selectionScopeReturnsSuppliedSelection() async throws {
        let doc = makeDocument(pages: ["Alpha page", "Beta page"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 }
        )
        let result = try await resolver.resolve(
            scope: .selection,
            currentLocator: .pdf(pageIndex: 0),
            selection: "highlighted"
        )
        #expect(result.scope == .selection)
        #expect(result.text == "highlighted")
        #expect(result.bookTitle == "Test Book")
        #expect(result.bookAuthor == "Test Author")
    }

    @Test("Page scope returns current page text")
    func pageScopeReturnsCurrentPageText() async throws {
        let doc = makeDocument(pages: ["Alpha unique", "Beta unique"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 1 }
        )
        let result = try await resolver.resolve(
            scope: .page,
            currentLocator: .pdf(pageIndex: 1),
            selection: nil
        )
        #expect(result.text.contains("Beta"))
        #expect(result.text.contains("Alpha") == false)
        #expect(result.pageNumber == 2)
        #expect(result.totalPages == 2)
    }

    @Test("Chapter scope concatenates pages in outline range")
    func chapterScopeReturnsRangeFromOutline() async throws {
        let doc = makeDocument(pages: ["Chapter one page one", "Chapter one page two", "Chapter two page one"])
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
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 }
        )
        let result = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        #expect(result.text.contains("Chapter one page one"))
        #expect(result.text.contains("Chapter one page two"))
        #expect(result.text.contains("Chapter two") == false)
        #expect(result.chapterTitle == "One")
    }

    @Test("Whole book scope joins all pages with budget")
    func wholeBookScopeJoinsAllPagesWithBudget() async throws {
        let doc = makeDocument(pages: ["First body", "Second body", "Third body"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 }
        )
        let result = try await resolver.resolve(
            scope: .wholeBook,
            currentLocator: .pdf(pageIndex: 0),
            selection: nil
        )
        #expect(result.text.contains("First"))
        #expect(result.text.contains("Second"))
        #expect(result.text.contains("Third"))
        #expect(result.truncated == false)
    }

    @Test("Selection scope without selection throws")
    func selectionScopeWithoutSelectionThrows() async {
        let doc = makeDocument(pages: ["Alpha"])
        let bridge = PDFContentBridge(document: doc, title: "Test Book")
        let resolver = PDFReaderContextResolver(
            bridge: bridge,
            book: makeBook(),
            currentPageProvider: { 0 }
        )
        await #expect(throws: ReaderContextError.self) {
            _ = try await resolver.resolve(
                scope: .selection,
                currentLocator: .pdf(pageIndex: 0),
                selection: nil
            )
        }
    }
}
#endif
