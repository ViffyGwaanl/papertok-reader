import Testing
import Foundation
@testable import PTReader

@Suite("PDFChapter")
struct PDFChapterTests {
    @Test("Chapter stores page range")
    func pageRange() {
        let chapter = PDFChapter(title: "Introduction", startPage: 0, endPage: 15)
        #expect(chapter.title == "Introduction")
        #expect(chapter.startPage == 0)
        #expect(chapter.endPage == 15)
        #expect(chapter.pageCount == 16)
    }

    @Test("Href format is pages:start-end")
    func hrefFormat() {
        let chapter = PDFChapter(title: "Ch 1", startPage: 5, endPage: 20)
        #expect(chapter.href == "pages:5-20")
    }

    @Test("Converts to ChapterEntry")
    func toChapterEntry() {
        let chapter = PDFChapter(title: "Results", startPage: 30, endPage: 45, level: 1)
        let entry = chapter.toChapterEntry()
        #expect(entry.title == "Results")
        #expect(entry.href == "pages:30-45")
        #expect(entry.level == 1)
    }

    @Test("Parses page range from href string")
    func parseHref() {
        let range = PDFChapter.parsePageRange(from: "pages:10-25")
        #expect(range?.startPage == 10)
        #expect(range?.endPage == 25)
    }

    @Test("Returns nil for invalid href")
    func invalidHref() {
        #expect(PDFChapter.parsePageRange(from: "/chapter1.xhtml") == nil)
        #expect(PDFChapter.parsePageRange(from: "pages:abc") == nil)
        #expect(PDFChapter.parsePageRange(from: "") == nil)
    }
}
