import Testing
import Foundation
@testable import PTReader

@Suite("EPUB search hit mapping")
struct EPUBSearchHitMappingTests {
    @Test("EPUB ContentSearchResult maps to ReaderSearchHit preserving cfi and snippet")
    func mapsEPUBResult() {
        let result = ContentSearchResult(
            text: "  vector calculus  ",
            chapterTitle: "Chapter 2",
            chapterHref: "/chapter2.xhtml",
            textBefore: "intro to ",
            textAfter: " in depth",
            progression: 0.42,
            locatorString: "stored::epubcfi(/6/4!/4/2)"
        )

        let hit = ReaderSearchHit.from(result)

        #expect(hit.snippet == "vector calculus")
        #expect(hit.chapterTitle == "Chapter 2")
        #expect(hit.contextBefore == "intro to ")
        #expect(hit.contextAfter == " in depth")
        #expect(hit.locator.cfi == "stored::epubcfi(/6/4!/4/2)")
        #expect(hit.locator.pageIndex == nil)
        #expect(hit.locator.progression == 0.42)
    }

    @Test("Multiple EPUB hits receive unique ids")
    func uniqueIDs() {
        let template = ContentSearchResult(
            text: "alpha",
            chapterTitle: "Ch",
            chapterHref: "/ch.xhtml",
            progression: 0.1,
            locatorString: "stored::epubcfi(/6/4!/4/2)"
        )

        let hits = (0..<5).map { _ in ReaderSearchHit.from(template) }
        let ids = Set(hits.map { $0.id })
        #expect(ids.count == hits.count)
    }

    @Test("EPUB mapping with nil locatorString yields nil cfi")
    func nilLocator() {
        let result = ContentSearchResult(
            text: "alpha",
            chapterTitle: "Ch",
            chapterHref: "/ch.xhtml"
        )
        let hit = ReaderSearchHit.from(result)
        #expect(hit.locator.cfi == nil)
        #expect(hit.locator.pageIndex == nil)
    }
}
