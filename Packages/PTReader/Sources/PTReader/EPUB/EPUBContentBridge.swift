 #if canImport(ReadiumShared)
import Foundation
import ReadiumShared

/// BookContentBridge implementation for EPUB publications using Readium.
///
/// Provides chapter-level and full-text content access, table of contents,
/// and text search for AI tools and the reader UI.
public final class EPUBContentBridge: BookContentBridge, @unchecked Sendable {
    private let publication: Publication

    public init(publication: Publication) {
        self.publication = publication
    }

    public var title: String {
        publication.metadata.title ?? "Unknown"
    }

    public var tableOfContents: [ChapterEntry] {
        get async throws {
            let result = await publication.tableOfContents()
            switch result {
            case .success(let links):
                return EPUBTOCMapper.map(links: links)
            case .failure:
                // Fall back to manifest TOC
                return EPUBTOCMapper.map(links: publication.manifest.tableOfContents)
            }
        }
    }

    public func extractChapterContent(href: String) async throws -> String {
        guard let resource = publication.get(Link(href: href)) else {
            throw EPUBOpenError.streamerError(href)
        }
        let readResult = await resource.read()
        switch readResult {
        case .success(let data):
            let html = String(data: data, encoding: .utf8) ?? ""
            return stripHTML(html)
        case .failure(let error):
            throw EPUBOpenError.streamerError("\(href): \(String(describing: error))")
        }
    }

    public func extractFullText() async throws -> String {
        // Use readingOrder for full text extraction since it contains all content resources
        // in reading order, while TOC may not cover everything
        var parts: [String] = []
        for link in publication.readingOrder {
            let text = try await extractChapterContent(href: link.href)
            if !text.isEmpty {
                parts.append(text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    public func searchContent(query: String) async throws -> [ContentSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.isEmpty == false else { return [] }

        switch await publication.search(query: normalizedQuery) {
        case .success(let iterator):
            var results: [ContentSearchResult] = []
            switch await iterator.forEach({ collection in
                results.append(contentsOf: collection.locators.map(Self.makeSearchResult(from:)))
            }) {
            case .success:
                return results
            case .failure(let error):
                throw EPUBOpenError.searchFailed(String(describing: error))
            }

        case .failure(let error):
            throw EPUBOpenError.searchFailed(String(describing: error))
        }
    }

    // MARK: - Private

    private static func makeSearchResult(from locator: Locator) -> ContentSearchResult {
        ContentSearchResult(
            text: locator.text.highlight ?? "",
            chapterTitle: locator.title ?? locator.href.string,
            chapterHref: locator.href.string,
            textBefore: locator.text.before ?? "",
            textAfter: locator.text.after ?? "",
            progression: locator.locations.progression ?? 0,
            locatorString: EPUBAnnotationBridge.storedString(from: locator)
        )
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
