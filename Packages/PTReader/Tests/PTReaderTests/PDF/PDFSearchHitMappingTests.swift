import Testing
import Foundation
@testable import PTReader

@Suite("PDF search hit mapping")
struct PDFSearchHitMappingTests {
    @Test("PDF ContentSearchResult maps to ReaderSearchHit with pageIndex from href")
    func mapsPDFResult() {
        let result = ContentSearchResult(
            text: "algebra",
            chapterTitle: "Page 7",
            chapterHref: "pages:6-6",
            textBefore: "see ",
            textAfter: " basics",
            progression: 0.5
        )

        let hit = ReaderSearchHit.from(result)

        #expect(hit.snippet == "algebra")
        #expect(hit.locator.pageIndex == 6)
        #expect(hit.locator.cfi == nil)
        #expect(hit.locator.progression == 0.5)
        #expect(hit.contextBefore == "see ")
        #expect(hit.contextAfter == " basics")
    }

    @Test("PDF mapping trims whitespace from snippet")
    func trimsSnippet() {
        let result = ContentSearchResult(
            text: "\n  hello  \n",
            chapterTitle: "Page 1",
            chapterHref: "pages:0-0"
        )
        let hit = ReaderSearchHit.from(result)
        #expect(hit.snippet == "hello")
    }

    @Test("Multiple PDF hits on same page still get distinct ids")
    func distinctIDs() {
        let r1 = ContentSearchResult(text: "x", chapterTitle: "Page 3", chapterHref: "pages:2-2")
        let r2 = ContentSearchResult(text: "x", chapterTitle: "Page 3", chapterHref: "pages:2-2")
        #expect(ReaderSearchHit.from(r1).id != ReaderSearchHit.from(r2).id)
    }

    @Test("Non-pages href yields nil pageIndex")
    func nonPageHref() {
        let result = ContentSearchResult(text: "y", chapterTitle: "T", chapterHref: "/something.xhtml")
        let hit = ReaderSearchHit.from(result)
        #expect(hit.locator.pageIndex == nil)
    }
}
