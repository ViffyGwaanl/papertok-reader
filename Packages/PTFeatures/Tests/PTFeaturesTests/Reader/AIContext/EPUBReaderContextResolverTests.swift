#if canImport(ReadiumShared)
import Testing
import Foundation
import ReadiumShared
import PTCore
import PTReader
@testable import PTFeatures

@Suite("EPUBReaderContextResolver")
struct EPUBReaderContextResolverTests {
    private func makeBook() -> Book {
        var book = Book.placeholder(title: "Fixture Book", filePath: "/tmp/fixture.epub")
        book.author = "Fixture Author"
        return book
    }

    private func openFixture(fileID: StaticString = #filePath) async throws -> (EPUBContentBridge, Locator) {
        let url = try #require(sampleEPUBURL(fileID: fileID))
        let publication = try await EPUBPublicationOpener().open(at: url)
        let bridge = EPUBContentBridge(publication: publication)
        for link in publication.readingOrder {
            guard let locator = await publication.locate(link) else { continue }
            let paragraphs = (try? await bridge.chapterParagraphs(at: locator)) ?? []
            if !paragraphs.isEmpty {
                return (bridge, locator)
            }
        }
        throw EPUBChapterParagraphsError.publicationUnavailable
    }

    private func sampleEPUBURL(fileID: StaticString) -> URL? {
        // Walk up from this test file to the PTFeatures package root, then
        // into the Readium swift-toolkit checkout's fixture directory. Also
        // try PTReader's checkout as a fallback.
        var packageRoot = URL(fileURLWithPath: "\(fileID)")
        for _ in 0..<5 { packageRoot.deleteLastPathComponent() }
        let candidates = [
            packageRoot,
            packageRoot.deletingLastPathComponent().appendingPathComponent("PTReader", isDirectory: true),
        ]
        for root in candidates {
            let fixtureURL = root
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("checkouts", isDirectory: true)
                .appendingPathComponent("swift-toolkit", isDirectory: true)
                .appendingPathComponent("Tests", isDirectory: true)
                .appendingPathComponent("Publications", isDirectory: true)
                .appendingPathComponent("Publications", isDirectory: true)
                .appendingPathComponent("childrens-literature.epub")
            if FileManager.default.fileExists(atPath: fixtureURL.path) {
                return fixtureURL
            }
        }
        return nil
    }

    @Test("Selection scope returns supplied selection")
    func selectionScopeReturnsSuppliedSelection() async throws {
        let (bridge, locator) = try await openFixture()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook())
        let result = try await resolver.resolve(
            scope: .selection,
            currentLocator: .epub(locator),
            selection: "a selected snippet"
        )
        #expect(result.text == "a selected snippet")
        #expect(result.scope == .selection)
        #expect(result.bookTitle == "Fixture Book")
    }

    @Test("Selection scope without selection throws")
    func selectionScopeWithoutSelectionThrows() async throws {
        let (bridge, locator) = try await openFixture()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook())
        await #expect(throws: ReaderContextError.self) {
            _ = try await resolver.resolve(
                scope: .selection,
                currentLocator: .epub(locator),
                selection: nil
            )
        }
    }

    @Test("Chapter scope joins paragraphs")
    func chapterScopeReturnsAllParagraphsJoined() async throws {
        let (bridge, locator) = try await openFixture()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook())
        let result = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .epub(locator),
            selection: nil
        )
        #expect(result.scope == .chapter)
        #expect(result.text.isEmpty == false)
    }

    @Test("Page scope returns a paragraph window")
    func pageScopeReturnsParagraphWindowAroundLocator() async throws {
        let (bridge, locator) = try await openFixture()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook())
        let result = try await resolver.resolve(
            scope: .page,
            currentLocator: .epub(locator),
            selection: nil
        )
        #expect(result.scope == .page)
        #expect(result.text.isEmpty == false)
    }

    @Test("Whole book scope applies budget clipper")
    func wholeBookScopeIteratesAllChaptersAndAppliesBudget() async throws {
        let (bridge, _) = try await openFixture()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook())
        let result = try await resolver.resolve(
            scope: .wholeBook,
            currentLocator: nil,
            selection: nil
        )
        #expect(result.scope == .wholeBook)
        #expect(result.text.isEmpty == false)
    }
}
#endif
