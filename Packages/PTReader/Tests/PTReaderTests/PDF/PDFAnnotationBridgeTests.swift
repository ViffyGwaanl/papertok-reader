import Foundation
import Testing
@testable import PTReader

#if canImport(PDFKit)
import PDFKit

@Suite("PDFAnnotationBridge")
@MainActor
struct PDFAnnotationBridgeTests {
    @Test("bookmark anchors round-trip and render on the bookmarked page")
    func bookmarkAnchorsRoundTrip() throws {
        let document = makeDocument(pageCount: 2)
        let noteID: Int64 = 41
        let anchor = PDFAnnotationAnchor.bookmark(pageIndex: 1, pageLabel: "Page 2")

        let stored = PDFAnnotationBridge.storedString(from: anchor)
        let restored = try #require(PDFAnnotationBridge.anchor(fromStoredString: stored))
        let rendered = PDFAnnotationBridge.renderedAnnotations(
            from: BookNote(
                id: noteID,
                bookId: 7,
                content: "Page 2",
                cfi: stored,
                chapter: "Page 2",
                type: NoteType.bookmark.rawValue,
                color: HighlightColor.yellow.hex,
                readerNote: nil,
                createTime: Date(),
                updateTime: Date()
            ),
            in: document
        )

        #expect(restored == anchor)
        #expect(rendered.count == 1)
        #expect(rendered[0].noteID == noteID)
        #expect(rendered[0].pageIndex == 1)
        #expect(rendered[0].type == .bookmark)
        #expect(rendered[0].bounds.width > 0)
        #expect(rendered[0].bounds.height > 0)
    }

    @Test("selection anchors render highlight bounds from normalized page rectangles")
    func selectionAnchorsRenderSelectionBounds() throws {
        let document = makeDocument(pageCount: 1)
        let pageBounds = try #require(document.page(at: 0)?.bounds(for: .mediaBox))
        let anchor = PDFAnnotationAnchor(
            kind: .selection,
            pageIndex: 0,
            pageLabel: "Page 1",
            rects: [
                .init(pageIndex: 0, normalizedX: 0.25, normalizedY: 0.5, normalizedWidth: 0.2, normalizedHeight: 0.1)
            ]
        )

        let stored = PDFAnnotationBridge.storedString(from: anchor)
        let rendered = PDFAnnotationBridge.renderedAnnotations(
            from: BookNote(
                id: 9,
                bookId: 2,
                content: "Selected text",
                cfi: stored,
                chapter: "Page 1",
                type: NoteType.note.rawValue,
                color: HighlightColor.purple.hex,
                readerNote: "Follow up",
                createTime: Date(),
                updateTime: Date()
            ),
            in: document
        )

        let expected = CGRect(
            x: pageBounds.minX + (pageBounds.width * 0.25),
            y: pageBounds.minY + (pageBounds.height * 0.5),
            width: pageBounds.width * 0.2,
            height: pageBounds.height * 0.1
        )

        #expect(rendered.count == 1)
        #expect(rendered[0].pageIndex == 0)
        #expect(rendered[0].type == .note)
        #expect(abs(rendered[0].bounds.minX - expected.minX) < 0.001)
        #expect(abs(rendered[0].bounds.minY - expected.minY) < 0.001)
        #expect(abs(rendered[0].bounds.width - expected.width) < 0.001)
        #expect(abs(rendered[0].bounds.height - expected.height) < 0.001)
        #expect(rendered[0].readerNote == "Follow up")
    }

    private func makeDocument(pageCount: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pageCount {
            document.insert(PDFPage(), at: index)
        }
        return document
    }
}
#endif
