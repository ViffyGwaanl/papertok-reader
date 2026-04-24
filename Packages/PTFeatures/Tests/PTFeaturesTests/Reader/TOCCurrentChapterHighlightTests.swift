import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("TOCCurrentChapterHighlight")
struct TOCCurrentChapterHighlightTests {
    @Test("Matching entry (by href) is flagged as current")
    func matchingEntryIsCurrent() {
        let entries = [
            ChapterEntry(title: "Intro", href: "chap1.xhtml"),
            ChapterEntry(title: "Chapter 1", href: "chap2.xhtml"),
            ChapterEntry(title: "Chapter 2", href: "chap3.xhtml"),
        ]
        let resolver = TOCHighlightResolver(entries: entries, currentHref: "chap2.xhtml", currentPage: nil)
        #expect(resolver.isCurrent(entry: entries[0]) == false)
        #expect(resolver.isCurrent(entry: entries[1]) == true)
        #expect(resolver.isCurrent(entry: entries[2]) == false)
    }

    @Test("Non-matching entries have no highlight")
    func nonMatchingHaveNoHighlight() {
        let entries = [
            ChapterEntry(title: "A", href: "a.xhtml"),
            ChapterEntry(title: "B", href: "b.xhtml"),
        ]
        let resolver = TOCHighlightResolver(entries: entries, currentHref: "z.xhtml", currentPage: nil)
        #expect(resolver.isCurrent(entry: entries[0]) == false)
        #expect(resolver.isCurrent(entry: entries[1]) == false)
    }

    @Test("Empty / nil current href leaves no highlight")
    func emptyCurrentHrefLeavesNoHighlight() {
        let entries = [
            ChapterEntry(title: "A", href: "a.xhtml"),
        ]
        let resolver = TOCHighlightResolver(entries: entries, currentHref: nil, currentPage: nil)
        #expect(resolver.isCurrent(entry: entries[0]) == false)
        let resolver2 = TOCHighlightResolver(entries: entries, currentHref: "", currentPage: nil)
        #expect(resolver2.isCurrent(entry: entries[0]) == false)
    }

    @Test("PDF pages-range href matches when currentPage is within the range")
    func pdfPageRangeMatches() {
        let entries = [
            ChapterEntry(title: "Chapter 1", href: "pages:0-4"),
            ChapterEntry(title: "Chapter 2", href: "pages:5-9"),
            ChapterEntry(title: "Chapter 3", href: "pages:10-19"),
        ]
        let resolver = TOCHighlightResolver(entries: entries, currentHref: nil, currentPage: 7)
        #expect(resolver.isCurrent(entry: entries[0]) == false)
        #expect(resolver.isCurrent(entry: entries[1]) == true)
        #expect(resolver.isCurrent(entry: entries[2]) == false)
    }

    @Test("href prefix match treats fragment-less EPUB hrefs as the same chapter")
    func epubHrefFragmentMatch() {
        let entries = [
            ChapterEntry(title: "Chapter 1", href: "chap1.xhtml"),
        ]
        let resolver = TOCHighlightResolver(
            entries: entries,
            currentHref: "chap1.xhtml#section-2",
            currentPage: nil
        )
        #expect(resolver.isCurrent(entry: entries[0]) == true)
    }
}
