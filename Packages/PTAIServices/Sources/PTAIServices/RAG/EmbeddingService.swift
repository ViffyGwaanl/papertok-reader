import Foundation
import PTCore
import PTNetworking

/// Service for generating vector embeddings via OpenAI-compatible `/v1/embeddings` API.
///
/// Used to power semantic / vector search over book content.
public actor EmbeddingService {
    public static let defaultModel = "text-embedding-3-small"
    public static let defaultDimensions = 1536
    public static let defaultBaseURL = URL(string: "https://api.openai.com")!

    private let apiKey: String?
    private let apiKeyKeychainKey: String?
    private let baseURL: URL
    private let model: String
    private let networkClient: NetworkClient
    /// Maximum number of inputs to send in a single `/v1/embeddings` request.
    private let maxBatchSize: Int

    public init(
        apiKey: String? = nil,
        apiKeyKeychainKey: String? = "openai_api_key",
        baseURL: URL = EmbeddingService.defaultBaseURL,
        model: String = EmbeddingService.defaultModel,
        networkClient: NetworkClient = NetworkClient(),
        maxBatchSize: Int = 100
    ) {
        self.apiKey = apiKey
        self.apiKeyKeychainKey = apiKeyKeychainKey
        self.baseURL = baseURL
        self.model = model
        self.networkClient = networkClient
        self.maxBatchSize = maxBatchSize
    }

    // MARK: - Public API

    /// Generate an embedding vector for a single piece of text.
    public func embed(_ text: String) async throws -> [Float] {
        let results = try await embedBatch([text])
        guard let first = results.first else {
            throw EmbeddingError.emptyResponse
        }
        return first
    }

    /// Generate embeddings for many inputs. Automatically chunks into batches of
    /// up to `maxBatchSize` per request and handles retries with exponential backoff
    /// for 429 / transient errors.
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        var output: [[Float]] = []
        output.reserveCapacity(texts.count)

        var index = 0
        while index < texts.count {
            let end = min(index + maxBatchSize, texts.count)
            let slice = Array(texts[index..<end])
            let batch = try await requestWithRetry(inputs: slice)
            output.append(contentsOf: batch)
            index = end
        }
        return output
    }

    // MARK: - Networking

    private func requestWithRetry(inputs: [String]) async throws -> [[Float]] {
        let maxAttempts = 5
        var attempt = 0
        var delay: UInt64 = 500_000_000 // 0.5s in ns

        while true {
            attempt += 1
            do {
                return try await performRequest(inputs: inputs)
            } catch let error as EmbeddingError {
                if case .rateLimited = error, attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delay)
                    delay *= 2
                    continue
                }
                if case .transient = error, attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delay)
                    delay *= 2
                    continue
                }
                throw error
            }
        }
    }

    private func performRequest(inputs: [String]) async throws -> [[Float]] {
        let key = try resolveAPIKey()
        let body = EmbeddingsRequestBody(model: model, input: inputs)
        let endpoint = Endpoint(
            method: .post,
            baseURL: baseURL,
            path: "/v1/embeddings",
            headers: [
                "Authorization": "Bearer \(key)",
                "Content-Type": "application/json"
            ],
            body: body,
            timeout: 120
        )

        let data: Data
        do {
            data = try await networkClient.requestRaw(endpoint)
        } catch let error as NetworkError {
            throw mapNetworkError(error)
        }

        let decoder = JSONDecoder()
        let decoded: EmbeddingsResponseBody
        do {
            decoded = try decoder.decode(EmbeddingsResponseBody.self, from: data)
        } catch {
            throw EmbeddingError.decodingFailed(error.localizedDescription)
        }

        // Ensure results are returned in request order, regardless of server ordering.
        let sorted = decoded.data.sorted { $0.index < $1.index }
        guard sorted.count == inputs.count else {
            throw EmbeddingError.mismatchedCount(expected: inputs.count, actual: sorted.count)
        }
        return sorted.map { $0.embedding }
    }

    private func resolveAPIKey() throws -> String {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        if let keychainKey = apiKeyKeychainKey {
            do {
                if let loaded = try KeychainService.load(key: keychainKey), !loaded.isEmpty {
                    return loaded
                }
            } catch {
                throw EmbeddingError.authenticationFailed("Keychain access failed: \(error.localizedDescription)")
            }
        }
        throw EmbeddingError.authenticationFailed("No API key available for embeddings")
    }

    private func mapNetworkError(_ error: NetworkError) -> EmbeddingError {
        switch error {
        case .httpError(let statusCode, let data):
            let message = data.flatMap { String(data: $0, encoding: .utf8) }
            switch statusCode {
            case 401, 403:
                return .authenticationFailed(message ?? "Unauthorized")
            case 429:
                return .rateLimited
            case 500...599:
                return .transient(message ?? "server \(statusCode)")
            default:
                return .serverError(statusCode: statusCode, message: message)
            }
        default:
            return .transient(error.localizedDescription)
        }
    }
}

// MARK: - Request / Response Types

private struct EmbeddingsRequestBody: Encodable, Sendable {
    let model: String
    let input: [String]
}

private struct EmbeddingsResponseBody: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let embedding: [Float]
        let index: Int
    }
    let data: [Item]
}

// MARK: - Errors

public enum EmbeddingError: LocalizedError, Sendable {
    case authenticationFailed(String)
    case rateLimited
    case transient(String)
    case serverError(statusCode: Int, message: String?)
    case emptyResponse
    case mismatchedCount(expected: Int, actual: Int)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg):
            let normalized = msg.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.contains("no api key") {
                return AppLocalization.string("errors.ai.no_api_key")
            }
            if normalized.contains("unauthorized")
                || normalized.contains("invalid api key")
                || normalized.contains("forbidden") {
                return AppLocalization.string("errors.ai.invalid_api_key")
            }
            return AppLocalization.string(
                "errors.ai.embeddings.authentication_failed",
                value: "Couldn't prepare embeddings."
            )
        case .rateLimited:
            return AppLocalization.string("errors.ai.rate_limited")
        case .transient:
            return AppLocalization.string(
                "errors.ai.embeddings.temporarily_unavailable",
                value: "Embeddings are temporarily unavailable."
            )
        case .serverError(let code, _):
            return AppLocalization.format(
                "errors.ai.embeddings.server_error_format",
                fallback: "The embeddings service returned an error (%lld).",
                locale: .autoupdatingCurrent,
                Int64(code)
            )
        case .emptyResponse:
            return AppLocalization.string(
                "errors.ai.embeddings.empty_response",
                value: "The embeddings service returned an empty response."
            )
        case .mismatchedCount(let expected, let actual):
            return AppLocalization.format(
                "errors.ai.embeddings.incomplete_response_format",
                fallback: "The embeddings service returned %lld results for %lld requests.",
                locale: .autoupdatingCurrent,
                Int64(actual),
                Int64(expected)
            )
        case .decodingFailed:
            return AppLocalization.string(
                "errors.ai.embeddings.decoding_failed",
                value: "Couldn't read the embeddings response."
            )
        }
    }
}
