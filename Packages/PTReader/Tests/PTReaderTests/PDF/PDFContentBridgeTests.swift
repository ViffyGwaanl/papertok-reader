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

    @Test("extractFullText falls back to OCR for scanned pages")
    func extractFullTextFallsBackToOCR() async throws {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)

        let bridge = PDFContentBridge(
            document: doc,
            title: "Scanned PDF",
            ocrTextProvider: { page in
                switch page {
                case 0:
                    return "Scanned first page"
                case 1:
                    return "Scanned second page"
                default:
                    return ""
                }
            }
        )

        let text = try await bridge.extractFullText()

        #expect(text.contains("Scanned first page"))
        #expect(text.contains("Scanned second page"))
    }

    @Test("extractChapterContent falls back to OCR for scanned page ranges")
    func extractChapterContentFallsBackToOCR() async throws {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)

        let bridge = PDFContentBridge(
            document: doc,
            title: "Scanned PDF",
            ocrTextProvider: { page in
                switch page {
                case 0:
                    return "Introduction"
                case 1:
                    return "Methods"
                default:
                    return ""
                }
            }
        )

        let text = try await bridge.extractChapterContent(href: "pages:1-1")

        #expect(text == "Methods")
    }

    @Test("searchContent finds matches in OCR fallback text")
    func searchContentFallsBackToOCR() async throws {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)

        let bridge = PDFContentBridge(
            document: doc,
            title: "Scanned PDF",
            ocrTextProvider: { page in
                switch page {
                case 0:
                    return "Optical character recognition keeps this page searchable."
                case 1:
                    return "No match here."
                default:
                    return ""
                }
            }
        )

        let results = try await bridge.searchContent(query: "searchable")

        #expect(results.count == 1)
        #expect(results.first?.chapterHref == "pages:0-0")
        #expect(results.first?.text == "searchable")
    }

    @Test("searchContent matches OCR text with Unicode-aware case-insensitive search")
    func searchContentMatchesUnicodeCaseInsensitively() async throws {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)

        let bridge = PDFContentBridge(
            document: doc,
            title: "Unicode PDF",
            ocrTextProvider: { _ in
                "İstanbul searchable"
            }
        )

        let results = try await bridge.searchContent(query: "istanbul")

        #expect(results.count == 1)
        #expect(results.first?.text == "İstanbul")
        #expect(results.first?.textAfter == " searchable")
    }

    @Test("searchContent reports the final page at full progression")
    func searchContentUsesFullProgressionForFinalPage() async throws {
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        doc.insert(PDFPage(), at: 1)

        let bridge = PDFContentBridge(
            document: doc,
            title: "Progression PDF",
            ocrTextProvider: { page in
                switch page {
                case 0:
                    return "No match here."
                case 1:
                    return "Final page searchable result."
                default:
                    return ""
                }
            }
        )

        let results = try await bridge.searchContent(query: "searchable")

        #expect(results.count == 1)
        #expect(results.first?.chapterHref == "pages:1-1")
        #expect(results.first?.progression == 1.0)
    }
}
#endif
