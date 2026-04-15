import Testing
import Foundation
@testable import PTReader

#if canImport(PDFKit)
import PDFKit

@Suite("PDFOutlineChapters")
@MainActor
struct PDFOutlineChaptersTests {
    private func makeDocument(pageCount: Int) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<pageCount {
            doc.insert(PDFPage(), at: i)
        }
        return doc
    }

    private func makeOutlineNode(label: String, page: PDFPage?) -> PDFOutline {
        let node = PDFOutline()
        node.label = label
        if let page {
            node.destination = PDFDestination(page: page, at: .zero)
        }
        return node
    }

    @Test("Returns empty array when document has no outline")
    func returnsEmptyForDocumentWithoutOutline() async {
        let doc = makeDocument(pageCount: 3)
        let bridge = PDFContentBridge(document: doc, title: "Test")
        let chapters = await bridge.outlineChapters()
        #expect(chapters.isEmpty)
    }

    @Test("Extracts top-level outline entries")
    func extractsTopLevelOutline() async {
        let doc = makeDocument(pageCount: 10)
        let root = PDFOutline()
        let ch1 = makeOutlineNode(label: "Chapter 1", page: doc.page(at: 0))
        let ch2 = makeOutlineNode(label: "Chapter 2", page: doc.page(at: 4))
        let ch3 = makeOutlineNode(label: "Chapter 3", page: doc.page(at: 7))
        root.insertChild(ch1, at: 0)
        root.insertChild(ch2, at: 1)
        root.insertChild(ch3, at: 2)
        doc.outlineRoot = root

        let bridge = PDFContentBridge(document: doc, title: "Test")
        let chapters = await bridge.outlineChapters()

        #expect(chapters.count == 3)
        #expect(chapters[0].title == "Chapter 1")
        #expect(chapters[0].pageIndex == 0)
        #expect(chapters[0].depth == 0)
        #expect(chapters[1].pageIndex == 4)
        #expect(chapters[2].pageIndex == 7)
    }

    @Test("Preserves nested depth for sub-chapters")
    func preservesNestedDepth() async {
        let doc = makeDocument(pageCount: 10)
        let root = PDFOutline()
        let ch1 = makeOutlineNode(label: "Chapter 1", page: doc.page(at: 0))
        let sub = makeOutlineNode(label: "Section 1.1", page: doc.page(at: 2))
        ch1.insertChild(sub, at: 0)
        root.insertChild(ch1, at: 0)
        doc.outlineRoot = root

        let bridge = PDFContentBridge(document: doc, title: "Test")
        let chapters = await bridge.outlineChapters()

        #expect(chapters.count == 1)
        #expect(chapters[0].depth == 0)
        #expect(chapters[0].children.count == 1)
        #expect(chapters[0].children[0].title == "Section 1.1")
        #expect(chapters[0].children[0].depth == 1)
        #expect(chapters[0].children[0].pageIndex == 2)
    }

    @Test("Skips outline nodes with missing destination")
    func skipsOutlineNodesWithMissingDestination() async {
        let doc = makeDocument(pageCount: 5)
        let root = PDFOutline()
        let ch1 = makeOutlineNode(label: "Chapter 1", page: doc.page(at: 0))
        let ghost = makeOutlineNode(label: "Ghost", page: nil)
        let ch3 = makeOutlineNode(label: "Chapter 3", page: doc.page(at: 3))
        root.insertChild(ch1, at: 0)
        root.insertChild(ghost, at: 1)
        root.insertChild(ch3, at: 2)
        doc.outlineRoot = root

        let bridge = PDFContentBridge(document: doc, title: "Test")
        let chapters = await bridge.outlineChapters()

        #expect(chapters.count == 2)
        #expect(chapters.map(\.title) == ["Chapter 1", "Chapter 3"])
    }

    @Test("Ids are stable across invocations")
    func idsAreStableAcrossInvocations() async {
        let doc = makeDocument(pageCount: 5)
        let root = PDFOutline()
        let ch1 = makeOutlineNode(label: "Alpha", page: doc.page(at: 0))
        let ch2 = makeOutlineNode(label: "Beta", page: doc.page(at: 2))
        root.insertChild(ch1, at: 0)
        root.insertChild(ch2, at: 1)
        doc.outlineRoot = root

        let bridge = PDFContentBridge(document: doc, title: "Test")
        let first = await bridge.outlineChapters()
        let second = await bridge.outlineChapters()

        #expect(first.map(\.id) == second.map(\.id))
        #expect(first[0].id != first[1].id)
    }
}
#endif
