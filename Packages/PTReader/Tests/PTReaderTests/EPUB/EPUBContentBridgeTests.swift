import Foundation
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

    @Test("searchContent mirrors Readium search locator metadata for navigation")
    func searchContentUsesReadiumLocatorSearchData() async throws {
        let sourceURL = try #require(sampleEPUBURL())
        let publication = try await EPUBPublicationOpener().open(at: sourceURL)
        let bridge = EPUBContentBridge(publication: publication)
        let query = "ugly duckling"

        let results = try await bridge.searchContent(query: query)
        let locators = try await searchLocators(publication: publication, query: query)

        let result = try #require(results.first)
        let locator = try #require(locators.first)

        #expect(result.chapterHref == locator.href.string)
        #expect(result.chapterTitle == (locator.title ?? locator.href.string))
        #expect(result.text == (locator.text.highlight ?? ""))
        #expect(result.textBefore == (locator.text.before ?? ""))
        #expect(result.textAfter == (locator.text.after ?? ""))
        #expect(result.progression == (locator.locations.progression ?? 0))
        let serializedLocator = try #require(result.locatorString)
        let exactLocator = try #require(EPUBAnnotationBridge.locator(fromStoredString: serializedLocator))
        #expect(exactLocator.href.string == locator.href.string)
        #expect(exactLocator.title == locator.title)
        #expect(exactLocator.text.highlight == locator.text.highlight)
        #expect(exactLocator.text.before == locator.text.before)
        #expect(exactLocator.text.after == locator.text.after)
        #expect(progressionsMatch(exactLocator.locations.progression, locator.locations.progression))
        #expect(progressionsMatch(exactLocator.locations.totalProgression, locator.locations.totalProgression))
    }

    private func sampleEPUBURL(fileID: StaticString = #filePath) -> URL? {
        var packageRoot = URL(fileURLWithPath: "\(fileID)")
        for _ in 0..<4 {
            packageRoot.deleteLastPathComponent()
        }

        let fixtureURL = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("checkouts", isDirectory: true)
            .appendingPathComponent("swift-toolkit", isDirectory: true)
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Publications", isDirectory: true)
            .appendingPathComponent("Publications", isDirectory: true)
            .appendingPathComponent("childrens-literature.epub")

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return nil
        }
        return fixtureURL
    }

    private func searchLocators(publication: Publication, query: String) async throws -> [Locator] {
        switch await publication.search(query: query) {
        case .success(let iterator):
            var locators: [Locator] = []
            switch await iterator.forEach({ collection in
                locators.append(contentsOf: collection.locators)
            }) {
            case .success:
                return locators
            case .failure(let error):
                throw error
            }
        case .failure(let error):
            throw error
        }
    }

    private func progressionsMatch(_ lhs: Double?, _ rhs: Double?, tolerance: Double = 1e-12) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs - rhs) < tolerance
        default:
            return false
        }
    }
}
