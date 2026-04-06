import Testing
@testable import PTReader
import ReadiumShared

@Suite("EPUBTOCMapper")
struct EPUBTOCMapperTests {
    @Test("flat link list maps to level-0 ChapterEntry")
    func flatLinks() {
        let links = [
            Link(href: "ch1.xhtml", title: "Chapter 1"),
            Link(href: "ch2.xhtml", title: "Chapter 2"),
        ]
        let entries = EPUBTOCMapper.map(links: links)
        #expect(entries.count == 2)
        #expect(entries[0].href == "ch1.xhtml")
        #expect(entries[0].title == "Chapter 1")
        #expect(entries[0].level == 0)
        #expect(entries[1].href == "ch2.xhtml")
        #expect(entries[1].title == "Chapter 2")
    }

    @Test("nested links map with correct levels")
    func nestedLinks() {
        let child = Link(href: "ch1-1.xhtml", title: "Section 1")
        let parent = Link(href: "ch1.xhtml", title: "Chapter 1", children: [child])
        let entries = EPUBTOCMapper.map(links: [parent])
        #expect(entries.count == 2)
        #expect(entries[0].level == 0)
        #expect(entries[0].childCount == 1)
        #expect(entries[1].level == 1)
        #expect(entries[1].href == "ch1-1.xhtml")
    }

    @Test("empty links produce empty result")
    func emptyLinks() {
        let entries = EPUBTOCMapper.map(links: [])
        #expect(entries.isEmpty)
    }

    @Test("deeply nested links map correctly")
    func deepNesting() {
        let grandchild = Link(href: "ch1-1-1.xhtml", title: "Sub-section 1.1")
        let child = Link(href: "ch1-1.xhtml", title: "Section 1", children: [grandchild])
        let parent = Link(href: "ch1.xhtml", title: "Chapter 1", children: [child])
        let entries = EPUBTOCMapper.map(links: [parent])
        #expect(entries.count == 3)
        #expect(entries[0].level == 0)
        #expect(entries[1].level == 1)
        #expect(entries[2].level == 2)
    }

    @Test("link without title uses href as title")
    func missingTitle() {
        let link = Link(href: "ch1.xhtml")
        let entries = EPUBTOCMapper.map(links: [link])
        #expect(entries.count == 1)
        #expect(entries[0].title == "ch1.xhtml")
    }
}
