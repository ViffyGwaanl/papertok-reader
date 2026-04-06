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
            throw EPUBOpenError.streamerError("Chapter not found: \(href)")
        }
        let readResult = await resource.read()
        switch readResult {
        case .success(let data):
            let html = String(data: data, encoding: .utf8) ?? ""
            return stripHTML(html)
        case .failure(let error):
            throw EPUBOpenError.streamerError("Failed to read chapter \(href): \(String(describing: error))")
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
        let toc = try await tableOfContents
        var results: [ContentSearchResult] = []
        let lowerQuery = query.lowercased()

        // Build a lookup for chapter titles by href
        let chapterTitles = Dictionary(toc.map { ($0.href, $0.title) }, uniquingKeysWith: { first, _ in first })

        for link in publication.readingOrder {
            let text: String
            do {
                text = try await extractChapterContent(href: link.href)
            } catch {
                continue
            }

            let lowerText = text.lowercased()
            var searchPos = lowerText.startIndex

            while let range = lowerText.range(of: lowerQuery, range: searchPos ..< lowerText.endIndex) {
                let snippetStart = lowerText.index(range.lowerBound, offsetBy: -60, limitedBy: lowerText.startIndex) ?? lowerText.startIndex
                let snippetEnd = lowerText.index(range.upperBound, offsetBy: 60, limitedBy: lowerText.endIndex) ?? lowerText.endIndex

                let matchedText = String(text[range])
                let textBefore = String(text[snippetStart ..< range.lowerBound])
                let textAfter = String(text[range.upperBound ..< snippetEnd])
                let chapterTitle = chapterTitles[link.href] ?? link.title ?? link.href

                results.append(ContentSearchResult(
                    text: matchedText,
                    chapterTitle: chapterTitle,
                    chapterHref: link.href,
                    textBefore: textBefore,
                    textAfter: textAfter
                ))
                searchPos = range.upperBound
            }
        }
        return results
    }

    // MARK: - Private

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
