#if canImport(ReadiumShared)
import Testing
import Foundation
import ReadiumShared
import PTAIServices
import PTCore
import PTReader
@testable import PTFeatures

@Suite("EPUBReaderContextResolver cache")
struct EPUBReaderContextResolverCacheTests {
    private func makeBook() -> Book {
        var book = Book.placeholder(title: "Fixture Book", filePath: "/tmp/fixture.epub")
        book.author = "Fixture Author"
        book.id = 42
        return book
    }

    private func sampleEPUBURL(fileID: StaticString) -> URL? {
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

    @Test("Chapter scope misses cache on first access")
    func chapterScopeMissesCacheOnFirstAccess() async throws {
        let (bridge, locator) = try await openFixture()
        let cache = BookContentCache()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook(), cache: cache)
        let before = await cache.count()
        #expect(before == 0)
        let result = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .epub(locator),
            selection: nil
        )
        #expect(result.text.isEmpty == false)
        let after = await cache.count()
        #expect(after == 1)
    }

    @Test("Chapter scope hits cache on second access")
    func chapterScopeHitsCacheOnSecondAccess() async throws {
        let (bridge, locator) = try await openFixture()
        let cache = BookContentCache()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook(), cache: cache)
        let first = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .epub(locator),
            selection: nil
        )
        // Seed a sentinel value for the same cache key to prove the second
        // call returns the cached value rather than recomputing.
        let href = locator.href.string
        let key = BookContentCache.Key(bookId: "42", scope: .epubChapter(href: href))
        await cache.set(key, value: "SENTINEL_CACHED_VALUE")
        let second = try await resolver.resolve(
            scope: .chapter,
            currentLocator: .epub(locator),
            selection: nil
        )
        #expect(first.text.isEmpty == false)
        #expect(second.text == "SENTINEL_CACHED_VALUE")
    }

    @Test("Whole book scope uses cache")
    func wholeBookScopeUsesCache() async throws {
        let (bridge, _) = try await openFixture()
        let cache = BookContentCache()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook(), cache: cache)
        _ = try await resolver.resolve(
            scope: .wholeBook,
            currentLocator: nil,
            selection: nil
        )
        let key = BookContentCache.Key(bookId: "42", scope: .epubWholeBook)
        let stored = await cache.get(key)
        #expect(stored != nil)
        #expect(stored?.isEmpty == false)
    }

    @Test("Selection scope bypasses cache")
    func selectionScopeBypassesCache() async throws {
        let (bridge, locator) = try await openFixture()
        let cache = BookContentCache()
        let resolver = EPUBReaderContextResolver(bridge: bridge, book: makeBook(), cache: cache)
        _ = try await resolver.resolve(
            scope: .selection,
            currentLocator: .epub(locator),
            selection: "a snippet"
        )
        let count = await cache.count()
        #expect(count == 0)
    }
}
#endif
