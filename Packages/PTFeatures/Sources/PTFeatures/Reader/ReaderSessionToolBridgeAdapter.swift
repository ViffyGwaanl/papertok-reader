import Foundation
import PTAIServices
import PTReader

public final class ReaderSessionToolBridgeAdapter: BookContentBridgeProtocol, @unchecked Sendable {
    private let bridge: any BookContentBridge

    public init(bridge: any BookContentBridge) {
        self.bridge = bridge
    }

    public func tableOfContentsJSON() async throws -> String {
        let toc = try await bridge.tableOfContents
        let chapters = toc.map { entry in
            [
                "title": entry.title,
                "href": entry.href,
                "level": entry.level,
                "child_count": entry.childCount,
            ] as [String: Any]
        }
        return Self.jsonString([
            "chapters": chapters,
            "count": chapters.count,
        ])
    }

    public func chapterContent(href: String) async throws -> String {
        try await bridge.extractChapterContent(href: href)
    }

    public func fullText() async throws -> String {
        try await bridge.extractFullText()
    }

    public func search(query: String) async throws -> String {
        let results = try await bridge.searchContent(query: query)
        let items = results.map { result in
            [
                "text": result.text,
                "chapter_title": result.chapterTitle,
                "chapter_href": result.chapterHref,
                "text_before": result.textBefore,
                "text_after": result.textAfter,
                "progression": result.progression,
            ] as [String: Any]
        }
        return Self.jsonString([
            "results": items,
            "count": items.count,
        ])
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
