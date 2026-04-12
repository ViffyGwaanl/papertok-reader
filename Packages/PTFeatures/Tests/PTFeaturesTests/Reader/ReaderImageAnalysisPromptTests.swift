import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("ReaderImageAnalysisPrompt")
struct ReaderImageAnalysisPromptTests {
    @Test("build includes book, chapter, and image metadata when available")
    func buildIncludesContextualMetadata() {
        let asset = ReaderImageAsset(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png",
            title: "Microscopy Plate",
            altText: "Cell sample",
            sourceURL: "chapter-2.xhtml#figure-3"
        )

        let prompt = ReaderImageAnalysisPrompt.build(
            for: asset,
            bookTitle: "PaperTok Reader Design",
            chapterTitle: "Chapter 2"
        )

        #expect(prompt.contains("PaperTok Reader Design"))
        #expect(prompt.contains("Chapter 2"))
        #expect(prompt.contains("Microscopy Plate"))
        #expect(prompt.contains("Cell sample"))
    }

    @Test("build omits empty optional metadata")
    func buildOmitsBlankMetadata() {
        let asset = ReaderImageAsset(
            data: Data([0xFF, 0xD8, 0xFF]),
            mimeType: "image/jpeg",
            title: "",
            altText: nil,
            sourceURL: nil
        )

        let prompt = ReaderImageAnalysisPrompt.build(
            for: asset,
            bookTitle: "Book Title",
            chapterTitle: ""
        )

        #expect(prompt.contains("Book Title"))
        #expect(prompt.contains("Image title") == false)
        #expect(prompt.contains("Alt text") == false)
        #expect(prompt.contains("Source") == false)
    }
}
