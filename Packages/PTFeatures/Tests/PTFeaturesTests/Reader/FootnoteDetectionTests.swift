import Foundation
import Testing
@testable import PTFeatures

@Suite("Footnote detection + popover content")
struct FootnoteDetectionTests {
    @Test("detectsFootnoteByHref with common fragment patterns")
    func detectsFootnoteByHref() {
        #expect(FootnoteDetector.isFootnote(href: "chapter-1.xhtml#fn-3"))
        #expect(FootnoteDetector.isFootnote(href: "chap.xhtml#footnote-5"))
        #expect(FootnoteDetector.isFootnote(href: "ch.xhtml#note1"))
        #expect(FootnoteDetector.isFootnote(href: "text.xhtml#fnref-2"))
    }

    @Test("nonFootnoteHrefProceeds as a normal navigation target")
    func nonFootnoteHrefProceeds() {
        #expect(FootnoteDetector.isFootnote(href: "chapter-2.xhtml#section-1") == false)
        #expect(FootnoteDetector.isFootnote(href: "intro.xhtml") == false)
        #expect(FootnoteDetector.isFootnote(href: "") == false)
        #expect(FootnoteDetector.isFootnote(href: "cover.xhtml#title") == false)
    }

    @Test("detection is case-insensitive for fragment patterns")
    func detectionIsCaseInsensitive() {
        #expect(FootnoteDetector.isFootnote(href: "chapter.xhtml#FN-1"))
        #expect(FootnoteDetector.isFootnote(href: "chapter.xhtml#FOOTNOTE-1"))
    }

    @Test("popoverContentRendersWithText shows the supplied body text")
    @MainActor
    func popoverContentRendersWithText() {
        let content = FootnotePopoverContent(
            title: "Footnote",
            body: "This is a sample footnote explaining the term.",
            sourceHref: "chapter.xhtml#fn-1"
        )
        #expect(content.body.isEmpty == false)
        #expect(content.body.contains("sample footnote"))
        #expect(content.sourceHref == "chapter.xhtml#fn-1")
    }
}
