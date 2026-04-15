#if canImport(ReadiumShared)
import CryptoKit
import Foundation
import ReadiumShared

/// A single paragraph-sized text element extracted from an EPUB chapter via
/// Readium's `ContentService`, carrying a full `Locator` suitable for
/// `applyDecorations` and `navigate(to:)`.
public struct EPUBChapterParagraph: Hashable, Identifiable, Sendable {
    public let id: String
    public let chapterHref: String
    public let role: Role
    public let text: String
    public let locator: Locator

    public enum Role: String, Hashable, Sendable, Codable {
        case body
        case heading
        case quote
        case footnote
        case other
    }

    public init(id: String, chapterHref: String, role: Role, text: String, locator: Locator) {
        self.id = id
        self.chapterHref = chapterHref
        self.role = role
        self.text = text
        self.locator = locator
    }
}

public enum EPUBChapterParagraphsError: Error, Equatable {
    case publicationUnavailable
    case contentServiceUnavailable
    case chapterNotFound(href: String)
}

extension EPUBContentBridge {
    /// Enumerates the paragraphs of the chapter containing `locator`, in
    /// document order. The returned paragraphs are clipped to the chapter
    /// whose href equals `locator.href`; iteration stops as soon as the
    /// underlying `ContentService` crosses into another resource.
    public func chapterParagraphs(at locator: Locator) async throws -> [EPUBChapterParagraph] {
        let chapterHref = locator.href.string
        let start = await resolveChapterStart(forHref: chapterHref) ?? locator
        return try await enumerateParagraphs(startingAt: start, chapterHref: chapterHref)
    }

    public func chapterParagraphs(href chapterHref: String) async throws -> [EPUBChapterParagraph] {
        guard let start = await resolveChapterStart(forHref: chapterHref) else {
            throw EPUBChapterParagraphsError.chapterNotFound(href: chapterHref)
        }
        return try await enumerateParagraphs(startingAt: start, chapterHref: start.href.string)
    }

    // MARK: - Private

    private func resolveChapterStart(forHref chapterHref: String) async -> Locator? {
        let candidates = publication.readingOrder + publication.manifest.tableOfContents
        let link = candidates.first { $0.href == chapterHref }
            ?? candidates.first { chapterHref.hasSuffix($0.href) || $0.href.hasSuffix(chapterHref) }
        guard let link else { return nil }
        return await publication.locate(link)
    }

    private func enumerateParagraphs(startingAt start: Locator, chapterHref: String) async throws -> [EPUBChapterParagraph] {
        guard let content = publication.content(from: start) else {
            throw EPUBChapterParagraphsError.contentServiceUnavailable
        }

        var result: [EPUBChapterParagraph] = []
        var index = 0
        for await element in content.sequence() {
            guard let text = element as? TextContentElement else {
                continue
            }
            let elementHref = text.locator.href.string
            if elementHref != chapterHref {
                // Clip to the requested chapter. `Publication.content(from:)`
                // iterates the whole publication forward; stop at the first
                // element that belongs to another resource.
                break
            }
            let joined = text.segments.map(\.text).joined()
            let normalized = Self.normalizeWhitespace(joined)
            guard !normalized.isEmpty else { continue }
            let role = Self.mapRole(text.role)
            // Stable ID: chapter href + ordinal index + SHA256 text prefix.
            // The index fixes order; the text hash protects against
            // re-ordering across re-enumerations of the same chapter.
            let id = Self.stableID(chapterHref: chapterHref, index: index, text: normalized)
            result.append(
                EPUBChapterParagraph(
                    id: id,
                    chapterHref: chapterHref,
                    role: role,
                    text: normalized,
                    locator: text.locator
                )
            )
            index += 1
        }
        return result
    }

    static func normalizeWhitespace(_ input: String) -> String {
        let collapsed = input.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mapRole(_ role: TextContentElement.Role) -> EPUBChapterParagraph.Role {
        switch role {
        case .body:
            return .body
        case .heading:
            return .heading
        case .quote:
            return .quote
        case .footnote:
            return .footnote
        }
    }

    static func stableID(chapterHref: String, index: Int, text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let prefix = hex.prefix(8)
        return "\(chapterHref)#p:\(index):\(prefix)"
    }
}
#endif
