import Testing
@testable import PTReader
import ReadiumShared

@Suite("EPUBContentBridge")
struct EPUBContentBridgeTests {
    /// Creates a minimal Publication with a TOC and reading order for testing.
    private func makeTestPublication(
        title: String = "Test Book",
        tocLinks: [Link] = [],
        readingOrder: [Link] = []
    ) -> Publication {
        Publication(
            manifest: Manifest(
                metadata: Metadata(title: title),
                readingOrder: readingOrder,
                tableOfContents: tocLinks
            )
        )
    }

    @Test("title returns Publication metadata title")
    func titleFromMetadata() {
        let pub = makeTestPublication(title: "My EPUB Book")
        let bridge = EPUBContentBridge(publication: pub)
        #expect(bridge.title == "My EPUB Book")
    }

    @Test("title returns Unknown when metadata has no title")
    func titleUnknown() {
        let pub = Publication(
            manifest: Manifest(
                metadata: Metadata(conformsTo: [.epub])
            )
        )
        let bridge = EPUBContentBridge(publication: pub)
        #expect(bridge.title == "Unknown")
    }

    @Test("tableOfContents returns mapped entries from manifest TOC")
    func tocFromManifest() async throws {
        let tocLinks = [
            Link(href: "ch1.xhtml", title: "Chapter 1"),
            Link(href: "ch2.xhtml", title: "Chapter 2"),
        ]
        let pub = makeTestPublication(tocLinks: tocLinks)
        let bridge = EPUBContentBridge(publication: pub)
        let toc = try await bridge.tableOfContents
        #expect(toc.count == 2)
        #expect(toc[0].title == "Chapter 1")
        #expect(toc[1].title == "Chapter 2")
    }
}
