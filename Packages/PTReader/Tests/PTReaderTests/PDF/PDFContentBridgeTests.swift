import Testing
import Foundation
@testable import PTReader

#if canImport(PDFKit)
import PDFKit

@Suite("PDFContentBridge")
@MainActor
struct PDFContentBridgeTests {
    @Test("Initializes with a PDFDocument")
    func initialization() {
        let doc = PDFDocument()
        let bridge = PDFContentBridge(document: doc, title: "Test PDF")
        #expect(bridge.title == "Test PDF")
    }

    @Test("Page count is correct")
    func pageCount() {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)
        doc.insert(PDFPage(), at: 2)
        let bridge = PDFContentBridge(document: doc, title: "Test")
        #expect(bridge.pageCount == 3)
    }

    @Test("extractPageText returns empty string for blank page")
    func extractBlankPage() {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        let bridge = PDFContentBridge(document: doc, title: "Test")
        let text = bridge.extractPageText(page: 0)
        #expect(text == "")
    }

    @Test("tableOfContents returns page-based chapters when no outline")
    func tocWithoutOutline() async throws {
        let doc = PDFDocument()
        for i in 0..<5 {
            doc.insert(PDFPage(), at: i)
        }
        let bridge = PDFContentBridge(document: doc, title: "Test")
        let toc = try await bridge.tableOfContents
        #expect(toc.count >= 1)
    }
}
#endif
