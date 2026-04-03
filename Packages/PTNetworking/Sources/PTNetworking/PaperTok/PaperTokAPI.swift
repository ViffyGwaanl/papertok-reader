import Foundation

/// REST client for the PaperTok academic paper API.
public struct PaperTokAPI: Sendable {
    private let client: NetworkClient
    private let baseURL: URL

    public init(
        client: NetworkClient = NetworkClient(),
        baseURL: URL = URL(string: "https://papertok.ai")!
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Fetch random papers for the feed.
    public func fetchRandomPapers(
        limit: Int = 20,
        language: String = "zh",
        day: String? = nil
    ) async throws -> [PaperTokCard] {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "lang", value: language),
        ]
        if let day, !day.isEmpty {
            queryItems.append(URLQueryItem(name: "day", value: day))
        }

        let endpoint = Endpoint(
            method: .get,
            baseURL: baseURL,
            path: "/api/papers/random",
            queryItems: queryItems,
            timeout: 30
        )
        return try await client.request(endpoint)
    }

    /// Fetch detail for a specific paper.
    public func fetchPaperDetail(
        id: Int,
        language: String = "zh"
    ) async throws -> PaperTokDetail {
        let endpoint = Endpoint(
            method: .get,
            baseURL: baseURL,
            path: "/api/papers/\(id)",
            queryItems: [URLQueryItem(name: "lang", value: language)],
            timeout: 30
        )
        return try await client.request(endpoint)
    }

    /// Resolve a relative URL to an absolute PaperTok URL.
    public func resolveURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("/") { return baseURL.absoluteString + trimmed }
        return baseURL.absoluteString + "/" + trimmed
    }
}
