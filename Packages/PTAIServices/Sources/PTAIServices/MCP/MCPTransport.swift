import Foundation
import PTNetworking

// MARK: - Transport Protocol

/// Abstraction over MCP message transport (HTTP+SSE, stdio, etc.).
public protocol MCPTransport: Sendable {
    func send(_ request: MCPRequest) async throws -> MCPResponse
    func notifications() -> AsyncThrowingStream<MCPNotification, Error>
    func connect() async throws
    func disconnect() async throws
}

// MARK: - HTTP + SSE Transport

/// MCP transport using HTTP POST for requests and SSE for server-initiated notifications.
///
/// Follows the MCP HTTP+SSE transport spec:
/// - Client sends JSON-RPC requests via POST to the server endpoint
/// - Server pushes notifications via an SSE stream
public actor MCPHTTPSSETransport: MCPTransport {
    private let serverURL: URL
    private let apiKey: String?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var sseTask: Task<Void, Never>?
    private var notificationContinuation: AsyncThrowingStream<MCPNotification, Error>.Continuation?
    private var isConnected = false

    public init(serverURL: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - MCPTransport

    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true
        startSSEStream()
    }

    public func disconnect() async throws {
        isConnected = false
        sseTask?.cancel()
        sseTask = nil
        notificationContinuation?.finish()
        notificationContinuation = nil
    }

    public func send(_ request: MCPRequest) async throws -> MCPResponse {
        guard isConnected else {
            throw MCPTransportError.notConnected
        }

        let body = try encoder.encode(request)

        var urlRequest = URLRequest(url: serverURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 30

        if let apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = body

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPTransportError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MCPTransportError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        return try decoder.decode(MCPResponse.self, from: data)
    }

    public nonisolated func notifications() -> AsyncThrowingStream<MCPNotification, Error> {
        AsyncThrowingStream { continuation in
            Task { await setNotificationContinuation(continuation) }
        }
    }

    // MARK: - SSE

    private func setNotificationContinuation(_ continuation: AsyncThrowingStream<MCPNotification, Error>.Continuation) {
        self.notificationContinuation = continuation
    }

    private func startSSEStream() {
        let sseURL = sseEndpointURL
        let key = apiKey
        sseTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: sseURL)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let apiKey = key {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                let (bytes, response) = try await self.session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    return
                }

                let events = SSEParser.events(from: bytes, heartbeatTimeout: 30)

                for try await event in events {
                    guard !Task.isCancelled else { break }
                    await self.handleSSEEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    await self.notificationContinuation?.finish(throwing: error)
                }
            }
        }
    }

    private var sseEndpointURL: URL {
        // MCP convention: SSE endpoint at /sse relative to server URL
        serverURL.appendingPathComponent("sse")
    }

    private func handleSSEEvent(_ event: SSEEvent) {
        guard let data = event.data.data(using: .utf8) else { return }

        if let notification = try? decoder.decode(MCPNotification.self, from: data) {
            notificationContinuation?.yield(notification)
        }
        // Ignore non-notification SSE events (e.g., endpoint info)
    }
}

// MARK: - Transport Errors

public enum MCPTransportError: Error, Sendable, LocalizedError {
    case notConnected
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP transport is not connected"
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .httpError(let code, let body):
            return "MCP HTTP error \(code)\(body.map { ": \($0)" } ?? "")"
        case .connectionFailed(let reason):
            return "MCP connection failed: \(reason)"
        }
    }
}
