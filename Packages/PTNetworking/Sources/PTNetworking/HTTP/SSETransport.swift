import Foundation

/// Protocol for Server-Sent Events transport, enabling pluggable SSE
/// connections (e.g. URLSession-based, WebSocket, or mock for tests).
public protocol SSETransportProtocol: Sendable {
    /// Open a persistent connection and return a stream of SSE events.
    func connect(url: URL, headers: [String: String]) -> AsyncThrowingStream<SSEEvent, Error>

    /// Tear down the connection. Safe to call multiple times.
    func disconnect()
}

/// Default SSE transport backed by `URLSession` async bytes and the
/// existing `SSEParser`.
public final class URLSessionSSETransport: SSETransportProtocol, @unchecked Sendable {
    private let session: URLSession
    private var activeTask: URLSessionDataTask?
    private let lock = NSLock()
    private let heartbeatTimeout: TimeInterval

    public init(
        session: URLSession = .shared,
        heartbeatTimeout: TimeInterval = 15
    ) {
        self.session = session
        self.heartbeatTimeout = heartbeatTimeout
    }

    public func connect(url: URL, headers: [String: String]) -> AsyncThrowingStream<SSEEvent, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let timeout = heartbeatTimeout

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await self.session.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200..<300).contains(httpResponse.statusCode) {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    let eventStream = SSEParser.events(from: bytes, heartbeatTimeout: timeout)
                    for try await event in eventStream {
                        if Task.isCancelled { break }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func disconnect() {
        lock.lock()
        activeTask?.cancel()
        activeTask = nil
        lock.unlock()
    }
}
