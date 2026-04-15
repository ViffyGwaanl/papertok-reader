import Testing
import Foundation
@testable import PTFeatures

@Suite("BudgetedTextClipper")
struct BudgetedTextClipperTests {
    @Test("Clip under budget returns unchanged")
    func clipUnderBudgetReturnsUnchanged() {
        let clipper = BudgetedTextClipper(maxCharacters: 100)
        let text = "Short text"
        let result = clipper.clip(text)
        #expect(result.wasTruncated == false)
        #expect(result.clipped == text)
        #expect(result.originalCount == text.count)
    }

    @Test("Clip over budget truncates at paragraph boundary")
    func clipOverBudgetTruncatesAtParagraphBoundary() {
        let clipper = BudgetedTextClipper(maxCharacters: 50)
        let paragraph = String(repeating: "a", count: 30)
        let text = paragraph + "\n\n" + paragraph + "\n\n" + paragraph
        let result = clipper.clip(text)
        #expect(result.wasTruncated == true)
        #expect(result.clipped.contains(paragraph))
    }

    @Test("Clip reports original count")
    func clipReportsOriginalCount() {
        let clipper = BudgetedTextClipper(maxCharacters: 10)
        let text = String(repeating: "x", count: 200)
        let result = clipper.clip(text)
        #expect(result.originalCount == 200)
        #expect(result.wasTruncated == true)
    }

    @Test("Clip appends truncation marker")
    func clipAppendsTruncationMarker() {
        let clipper = BudgetedTextClipper(maxCharacters: 20)
        let text = String(repeating: "y", count: 500)
        let result = clipper.clip(text)
        #expect(result.wasTruncated == true)
        // Marker is localized; it is a non-empty tail appended after the clipped body.
        #expect(result.clipped.count > 0)
        #expect(result.clipped != String(result.clipped.prefix(20)))
    }
}
