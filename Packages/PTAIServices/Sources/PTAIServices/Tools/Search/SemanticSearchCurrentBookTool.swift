import Foundation

public struct SemanticSearchCurrentBookTool: AITool {
    public static let name = "semantic_search_current_book"
    public static let description = "Vector embedding + keyword hybrid search within the currently reading book. Requires pre-built index."
    public static let category = ToolCategory.search
    public static let riskLevel = ToolRiskLevel.safe

    private let hybridSearch: HybridSearchService?

    public init(hybridSearch: HybridSearchService? = nil) {
        self.hybridSearch = hybridSearch
    }

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let hybridSearch else {
            return ToolResult(content: jsonString([
                "status": "not_implemented",
                "note": "Semantic search index not yet built. Use book_content_search for keyword search."
            ]))
        }

        let query = (arguments["query"] as? String) ?? ""
        let limit = (arguments["limit"] as? Int) ?? 10
        guard !query.isEmpty else {
            return ToolResult(content: jsonString(["error": "missing query"]), isError: true)
        }

        let bookId = context.activeBookId ?? context.bookId
        guard let bookId else {
            return ToolResult(content: jsonString([
                "status": "no_active_book",
                "note": "No currently-reading book available for semantic search."
            ]))
        }

        do {
            let results = try await hybridSearch.search(query: query, bookId: bookId, limit: limit)
            let payload: [[String: Any]] = results.map { r in
                [
                    "text": r.text,
                    "score": r.score,
                    "source": r.source.rawValue,
                    "book_id": r.bookId,
                    "chapter": r.chapter ?? "",
                ]
            }
            return ToolResult(content: jsonString([
                "status": "ok",
                "count": results.count,
                "results": payload,
            ]))
        } catch {
            return ToolResult(
                content: jsonString(["error": error.localizedDescription]),
                isError: true
            )
        }
    }
}
