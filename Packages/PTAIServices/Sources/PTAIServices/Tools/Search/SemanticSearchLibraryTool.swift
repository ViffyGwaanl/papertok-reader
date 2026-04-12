import Foundation

public struct SemanticSearchLibraryTool: AITool {
    public static let name = "semantic_search_library"
    public static let description = "Hybrid vector+BM25 search across the entire library. Requires pre-built RAG index."
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
                "note": "Library index not yet built."
            ]))
        }

        let query = (arguments["query"] as? String) ?? ""
        let limit = (arguments["limit"] as? Int) ?? 10
        guard !query.isEmpty else {
            return ToolResult(content: jsonString(["error": "missing query"]), isError: true)
        }

        do {
            let results = try await hybridSearch.search(query: query, bookId: nil, limit: limit)
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
