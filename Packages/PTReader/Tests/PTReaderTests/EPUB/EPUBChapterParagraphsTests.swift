import Foundation
import Testing
@testable import PTReader
import ReadiumShared

@Suite("EPUBChapterParagraphs")
struct EPUBChapterParagraphsTests {
    @Test("enumerates paragraphs of the first chapter in document order")
    func enumeratesParagraphsInOrder() async throws {
        let (bridge, firstLocator, _) = try await openFixture()
        let paragraphs = try await bridge.chapterParagraphs(at: firstLocator)
        #expect(paragraphs.count >= 2)
        let hrefs = Set(paragraphs.map(\.chapterHref))
        #expect(hrefs.count == 1)
        #expect(hrefs.first == firstLocator.href.string)
    }

    @Test("clips enumeration to the requested chapter")
    func clipsToCurrentChapter() async throws {
        let (bridge, firstLocator, secondLocator) = try await openFixture()
        let firstParagraphs = try await bridge.chapterParagraphs(at: firstLocator)
        let secondHref = secondLocator.href.string
        #expect(firstParagraphs.allSatisfy { $0.chapterHref != secondHref })
    }

    @Test("returns stable IDs across invocations")
    func stableIDsAcrossInvocations() async throws {
        let (bridge, firstLocator, _) = try await openFixture()
        let a = try await bridge.chapterParagraphs(at: firstLocator)
        let b = try await bridge.chapterParagraphs(at: firstLocator)
        #expect(a.count == b.count)
        for (lhs, rhs) in zip(a, b) {
            #expect(lhs.id == rhs.id)
            #expect(lhs.text == rhs.text)
        }
    }

    @Test("coalesces segments and collapses inner whitespace")
    func coalescesSegmentsAndCollapsesWhitespace() async throws {
        let (bridge, firstLocator, _) = try await openFixture()
        let paragraphs = try await bridge.chapterParagraphs(at: firstLocator)
        for paragraph in paragraphs {
            #expect(paragraph.text.contains("  ") == false)
            #expect(paragraph.text.contains("\n") == false)
            #expect(paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines) == paragraph.text)
        }
    }

    @Test("filters empty paragraphs")
    func filtersEmptyParagraphs() async throws {
        let (bridge, firstLocator, _) = try await openFixture()
        let paragraphs = try await bridge.chapterParagraphs(at: firstLocator)
        #expect(paragraphs.allSatisfy { !$0.text.isEmpty })
    }

    @Test("maps every Readium TextContentElement.Role case to a simplified role")
    func roleMappingPreservesHeadings() throws {
        // Unit-level: the simplified Role enum must cover every Readium case
        // exhaustively. Readium's HTMLResourceContentIterator currently only
        // emits .body at runtime, so we verify the mapping directly to keep
        // this contract test independent of fixture content.
        #expect(EPUBContentBridge.mapRole(.body) == .body)
        #expect(EPUBContentBridge.mapRole(.heading(level: 1)) == .heading)
        #expect(EPUBContentBridge.mapRole(.heading(level: 3)) == .heading)
        #expect(EPUBContentBridge.mapRole(.quote(referenceUrl: nil, referenceTitle: nil)) == .quote)
        #expect(EPUBContentBridge.mapRole(.footnote) == .footnote)
    }

    @Test("href overload returns the same set as the locator overload")
    func hrefOverloadResolves() async throws {
        let (bridge, firstLocator, _) = try await openFixture()
        let viaLocator = try await bridge.chapterParagraphs(at: firstLocator)
        let viaHref = try await bridge.chapterParagraphs(href: firstLocator.href.string)
        #expect(viaLocator.map(\.id) == viaHref.map(\.id))
    }

    @Test("unknown href throws chapterNotFound")
    func unknownHrefThrows() async throws {
        let (bridge, _, _) = try await openFixture()
        await #expect(throws: EPUBChapterParagraphsError.self) {
            _ = try await bridge.chapterParagraphs(href: "/does/not/exist.xhtml")
        }
    }

    // MARK: - Fixture helpers

    private func openFixture(fileID: StaticString = #filePath) async throws -> (EPUBContentBridge, Locator, Locator) {
        let url = try #require(sampleEPUBURL(fileID: fileID))
        let publication = try await EPUBPublicationOpener().open(at: url)
        let bridge = EPUBContentBridge(publication: publication)
        let readingOrder = publication.readingOrder
        #expect(readingOrder.count >= 2)
        // Pick the first two reading-order resources that actually yield
        // paragraphs (skip cover/nav pages with no body text).
        var contentLocators: [Locator] = []
        for link in readingOrder {
            guard let locator = await publication.locate(link) else { continue }
            let paragraphs = (try? await bridge.chapterParagraphs(at: locator)) ?? []
            if !paragraphs.isEmpty {
                contentLocators.append(locator)
                if contentLocators.count == 2 { break }
            }
        }
        #expect(contentLocators.count == 2)
        return (bridge, contentLocators[0], contentLocators[1])
    }

    private func sampleEPUBURL(fileID: StaticString) -> URL? {
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
}
