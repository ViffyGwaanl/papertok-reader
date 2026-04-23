import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("TOC Search Filter")
struct TOCSearchTests {
    private let entries: [ChapterEntry] = [
        ChapterEntry(title: "Preface", href: "pages:0-5"),
        ChapterEntry(title: "Chapter 1: Introduction", href: "pages:6-20"),
        ChapterEntry(title: "Chapter 2: Advanced Topics", href: "pages:21-50"),
        ChapterEntry(title: "第三章 深入探索", href: "pages:51-80"),
        ChapterEntry(title: "Appendix A", href: "pages:81-90"),
    ]

    @Test("emptyQueryShowsAllEntries returns the full list")
    func emptyQueryShowsAllEntries() {
        let result = TOCSearchFilter.filter(entries, query: "")
        #expect(result.count == entries.count)
    }

    @Test("emptyQueryShowsAllEntries also accepts whitespace-only")
    func whitespaceQueryShowsAllEntries() {
        let result = TOCSearchFilter.filter(entries, query: "   ")
        #expect(result.count == entries.count)
    }

    @Test("nonEmptyQueryFiltersByTitle keeps matching entries only")
    func nonEmptyQueryFiltersByTitle() {
        let result = TOCSearchFilter.filter(entries, query: "Chapter")
        #expect(result.count == 2)
        #expect(result.map(\.title).contains("Chapter 1: Introduction"))
        #expect(result.map(\.title).contains("Chapter 2: Advanced Topics"))
    }

    @Test("searchIsCaseInsensitive")
    func searchIsCaseInsensitive() {
        let upper = TOCSearchFilter.filter(entries, query: "PREFACE")
        let lower = TOCSearchFilter.filter(entries, query: "preface")
        #expect(upper.count == 1)
        #expect(lower.count == 1)
        #expect(upper.first?.title == "Preface")
    }

    @Test("pinyinSearchFindsChineseTitles via localizedStandardContains")
    func pinyinSearchFindsChineseTitles() {
        // localizedStandardContains performs locale-aware, diacritic-
        // insensitive matching. The CJK substring should match its
        // containing title.
        let result = TOCSearchFilter.filter(entries, query: "深入")
        #expect(result.count == 1)
        #expect(result.first?.title == "第三章 深入探索")
    }

    @Test("queryWithNoMatchesReturnsEmpty")
    func queryWithNoMatchesReturnsEmpty() {
        let result = TOCSearchFilter.filter(entries, query: "zzzzzz")
        #expect(result.isEmpty)
    }
}
