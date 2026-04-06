# Phase 2: PTNetworking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PTNetworking Swift package — a generic HTTP client, SSE stream parser, WebDAV sync client, and PaperTok REST API client — all built on URLSession with full async/await and Sendable conformance.

**Architecture:** PTNetworking depends only on PTCore and Foundation. `NetworkClient` is an actor wrapping URLSession for type-safe HTTP. `SSEParser` converts `URLSession.AsyncBytes` into `AsyncThrowingStream<SSEEvent>`. `WebDAVClient` is an actor implementing PROPFIND/GET/PUT/DELETE/MKCOL via XML. `PaperTokAPI` is a thin REST client for `papertok.ai`.

**Tech Stack:** Swift 5.9+, URLSession, Foundation (XMLParser), PTCore, Swift Testing (`import Testing`)

---

## File Structure

```
Packages/PTNetworking/
├── Package.swift
├── Sources/PTNetworking/
│   ├── PTNetworking.swift              # Module-level re-exports
│   ├── HTTP/
│   │   ├── HTTPMethod.swift            # GET, POST, PUT, DELETE, PATCH, PROPFIND, MKCOL
│   │   ├── Endpoint.swift              # Request descriptor struct
│   │   ├── NetworkError.swift          # Typed error enum
│   │   └── NetworkClient.swift         # actor — generic HTTP client
│   ├── SSE/
│   │   ├── SSEEvent.swift              # Parsed SSE event struct
│   │   └── SSEParser.swift             # Line-based SSE parser → AsyncThrowingStream
│   ├── WebDAV/
│   │   ├── RemoteFile.swift            # File/directory metadata model
│   │   ├── WebDAVAuth.swift            # Basic/Digest auth enum
│   │   └── WebDAVClient.swift          # actor — WebDAV operations
│   └── PaperTok/
│       ├── PaperTokModels.swift        # PaperTokCard, PaperTokDetail, PaperTokGeneratedImage
│       └── PaperTokAPI.swift           # REST client for papertok.ai
└── Tests/PTNetworkingTests/
    ├── HTTP/
    │   ├── EndpointTests.swift         # URL construction, header merging
    │   └── NetworkClientTests.swift    # URLProtocol-stubbed request/response
    ├── SSE/
    │   └── SSEParserTests.swift        # Line parsing, multi-line data, heartbeat
    ├── WebDAV/
    │   └── WebDAVClientTests.swift     # PROPFIND XML parsing, auth headers
    └── PaperTok/
        └── PaperTokModelsTests.swift   # JSON decoding from real API shapes
```

---

### Task 1: Package.swift and Module Entry

**Files:**
- Create: `Packages/PTNetworking/Package.swift`
- Create: `Packages/PTNetworking/Sources/PTNetworking/PTNetworking.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTNetworking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTNetworking", targets: ["PTNetworking"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
    ],
    targets: [
        .target(
            name: "PTNetworking",
            dependencies: ["PTCore"]
        ),
        .testTarget(
            name: "PTNetworkingTests",
            dependencies: ["PTNetworking"]
        ),
    ]
)
```

- [ ] **Step 2: Create module entry file**

```swift
// PTNetworking — HTTP, SSE, WebDAV, and PaperTok API layer
// Depends on PTCore for shared models and configuration

import Foundation
@_exported import PTCore
```

- [ ] **Step 3: Create placeholder test file so the package resolves**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/PTNetworkingImportTests.swift`:

```swift
import Testing
@testable import PTNetworking

@Suite("PTNetworking Module")
struct PTNetworkingImportTests {
    @Test("Module imports successfully")
    func moduleImports() {
        // If this compiles, the module and its PTCore re-export work
        #expect(true)
    }
}
```

- [ ] **Step 4: Verify package resolves and test passes**

Run:
```bash
cd Packages/PTNetworking && swift test 2>&1 | tail -20
```
Expected: `Test run started` ... `passed`

- [ ] **Step 5: Commit**

```bash
git add Packages/PTNetworking/Package.swift Packages/PTNetworking/Sources/PTNetworking/PTNetworking.swift Packages/PTNetworking/Tests/PTNetworkingTests/PTNetworkingImportTests.swift
git commit -m "feat(PTNetworking): initialize package with PTCore dependency"
```

---

### Task 2: HTTPMethod and Endpoint

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/HTTP/HTTPMethod.swift`
- Create: `Packages/PTNetworking/Sources/PTNetworking/HTTP/Endpoint.swift`
- Test: `Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/EndpointTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/EndpointTests.swift`:

```swift
import Testing
import Foundation
@testable import PTNetworking

@Suite("Endpoint")
struct EndpointTests {
    @Test("Builds URL with path and query items")
    func urlConstruction() throws {
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://api.example.com")!,
            path: "/v1/papers",
            queryItems: [URLQueryItem(name: "lang", value: "zh"), URLQueryItem(name: "limit", value: "20")]
        )
        let request = try endpoint.urlRequest()
        let url = request.url!
        #expect(url.scheme == "https")
        #expect(url.host == "api.example.com")
        #expect(url.path == "/v1/papers" || url.path() == "/v1/papers")
        #expect(url.query!.contains("lang=zh"))
        #expect(url.query!.contains("limit=20"))
        #expect(request.httpMethod == "GET")
    }

    @Test("Merges custom headers")
    func headerMerging() throws {
        let endpoint = Endpoint(
            method: .post,
            baseURL: URL(string: "https://api.example.com")!,
            path: "/chat",
            headers: ["Authorization": "Bearer sk-123", "X-Custom": "value"]
        )
        let request = try endpoint.urlRequest()
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-123")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpMethod == "POST")
    }

    @Test("Encodes JSON body")
    func jsonBodyEncoding() throws {
        struct Payload: Encodable {
            let message: String
            let count: Int
        }
        let endpoint = Endpoint(
            method: .post,
            baseURL: URL(string: "https://api.example.com")!,
            path: "/send",
            body: Payload(message: "hello", count: 42)
        )
        let request = try endpoint.urlRequest()
        let data = request.httpBody!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["message"] as? String == "hello")
        #expect(json["count"] as? Int == 42)
    }

    @Test("Timeout defaults to 30 seconds")
    func defaultTimeout() throws {
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/"
        )
        let request = try endpoint.urlRequest()
        #expect(request.timeoutInterval == 30)
    }

    @Test("Custom timeout is applied")
    func customTimeout() throws {
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/",
            timeout: 60
        )
        let request = try endpoint.urlRequest()
        #expect(request.timeoutInterval == 60)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTNetworking && swift test --filter EndpointTests 2>&1 | tail -10`
Expected: FAIL — `Endpoint` and `HTTPMethod` not found.

- [ ] **Step 3: Create HTTPMethod**

Create `Packages/PTNetworking/Sources/PTNetworking/HTTP/HTTPMethod.swift`:

```swift
import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case propfind = "PROPFIND"
    case mkcol = "MKCOL"
}
```

- [ ] **Step 4: Create Endpoint**

Create `Packages/PTNetworking/Sources/PTNetworking/HTTP/Endpoint.swift`:

```swift
import Foundation

public struct Endpoint: Sendable {
    public let method: HTTPMethod
    public let baseURL: URL
    public let path: String
    public var headers: [String: String]
    public var queryItems: [URLQueryItem]?
    public var body: (any Encodable & Sendable)?
    public var timeout: TimeInterval

    public init(
        method: HTTPMethod,
        baseURL: URL,
        path: String,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable & Sendable)? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.baseURL = baseURL
        self.path = path
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
        self.timeout = timeout
    }

    public func urlRequest() throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout

        // Default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Custom headers override defaults
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }
}

// Type-erased Encodable wrapper for Sendable conformance
internal struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init(_ value: any Encodable & Sendable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTNetworking && swift test --filter EndpointTests 2>&1 | tail -10`
Expected: All 5 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/HTTP/HTTPMethod.swift Packages/PTNetworking/Sources/PTNetworking/HTTP/Endpoint.swift Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/EndpointTests.swift
git commit -m "feat(PTNetworking): add HTTPMethod enum and Endpoint struct with URL building"
```

---

### Task 3: NetworkError

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkError.swift`

- [ ] **Step 1: Create NetworkError**

```swift
import Foundation

public enum NetworkError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case noData
    case timeout
    case cancelled
    case connectionLost
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .httpError(let statusCode, _):
            return "HTTP error \(statusCode)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .connectionLost:
            return "Network connection lost"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    /// Map a URLError to a typed NetworkError.
    static func from(_ error: Error) -> NetworkError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            case .networkConnectionLost, .notConnectedToInternet:
                return .connectionLost
            default:
                return .unknown(urlError)
            }
        }
        return .unknown(error)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkError.swift
git commit -m "feat(PTNetworking): add NetworkError with URLError mapping"
```

---

### Task 4: NetworkClient

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkClient.swift`
- Test: `Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/NetworkClientTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/NetworkClientTests.swift`:

```swift
import Testing
import Foundation
@testable import PTNetworking

// Stub URLProtocol for testing without real network
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var responseStatusCode: Int = 200
    nonisolated(unsafe) static var responseHeaders: [String: String] = ["Content-Type": "application/json"]
    nonisolated(unsafe) static var responseError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = Self.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("NetworkClient")
struct NetworkClientTests {
    init() {
        StubURLProtocol.responseData = nil
        StubURLProtocol.responseStatusCode = 200
        StubURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        StubURLProtocol.responseError = nil
    }

    private func makeClient() -> NetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return NetworkClient(configuration: config)
    }

    @Test("Decodes JSON response")
    func decodesJSON() async throws {
        struct Item: Decodable, Equatable { let name: String; let count: Int }
        StubURLProtocol.responseData = #"{"name":"test","count":5}"#.data(using: .utf8)

        let client = makeClient()
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/item"
        )
        let item: Item = try await client.request(endpoint)
        #expect(item.name == "test")
        #expect(item.count == 5)
    }

    @Test("Returns raw data")
    func returnsRawData() async throws {
        let payload = "raw bytes".data(using: .utf8)!
        StubURLProtocol.responseData = payload

        let client = makeClient()
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/raw"
        )
        let data = try await client.requestRaw(endpoint)
        #expect(data == payload)
    }

    @Test("Throws httpError on 404")
    func httpError404() async throws {
        StubURLProtocol.responseStatusCode = 404
        StubURLProtocol.responseData = "not found".data(using: .utf8)

        let client = makeClient()
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/missing"
        )
        await #expect(throws: NetworkError.self) {
            let _: String = try await client.request(endpoint)
        }
    }

    @Test("Throws decodingFailed on bad JSON")
    func decodingFailed() async throws {
        StubURLProtocol.responseData = "not json".data(using: .utf8)

        let client = makeClient()
        let endpoint = Endpoint(
            method: .get,
            baseURL: URL(string: "https://example.com")!,
            path: "/bad"
        )
        await #expect(throws: NetworkError.self) {
            struct Item: Decodable { let id: Int }
            let _: Item = try await client.request(endpoint)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTNetworking && swift test --filter NetworkClientTests 2>&1 | tail -10`
Expected: FAIL — `NetworkClient` not found.

- [ ] **Step 3: Implement NetworkClient**

Create `Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkClient.swift`:

```swift
import Foundation

public actor NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        configuration: URLSessionConfiguration = .default,
        decoder: JSONDecoder = {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            d.dateDecodingStrategy = .iso8601
            return d
        }()
    ) {
        self.session = URLSession(configuration: configuration)
        self.decoder = decoder
    }

    /// Send a request and decode the JSON response into `T`.
    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await requestRaw(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    /// Send a request and return the raw response `Data`.
    public func requestRaw(_ endpoint: Endpoint) async throws -> Data {
        let urlRequest: URLRequest
        do {
            urlRequest = try endpoint.urlRequest()
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.unknown(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetworkError.from(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return data
    }

    /// Upload raw data to an endpoint.
    public func upload(_ endpoint: Endpoint, data: Data) async throws {
        var urlRequest = try endpoint.urlRequest()
        urlRequest.httpBody = data

        let (_, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NetworkError.httpError(statusCode: statusCode, data: nil)
        }
    }

    /// Download data from an endpoint and write to a file URL.
    public func download(_ endpoint: Endpoint, to fileURL: URL) async throws {
        let urlRequest = try endpoint.urlRequest()

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: urlRequest)
        } catch {
            throw NetworkError.from(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NetworkError.httpError(statusCode: statusCode, data: nil)
        }

        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }

    /// Open a byte stream for SSE or streaming responses.
    public func bytes(_ endpoint: Endpoint) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let urlRequest = try endpoint.urlRequest()

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch {
            throw NetworkError.from(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NetworkError.httpError(statusCode: statusCode, data: nil)
        }

        return (bytes, httpResponse)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PTNetworking && swift test --filter NetworkClientTests 2>&1 | tail -15`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkClient.swift Packages/PTNetworking/Tests/PTNetworkingTests/HTTP/NetworkClientTests.swift
git commit -m "feat(PTNetworking): add NetworkClient actor with JSON/raw/upload/download/bytes"
```

---

### Task 5: SSEEvent and SSEParser

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/SSE/SSEEvent.swift`
- Create: `Packages/PTNetworking/Sources/PTNetworking/SSE/SSEParser.swift`
- Test: `Packages/PTNetworking/Tests/PTNetworkingTests/SSE/SSEParserTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/SSE/SSEParserTests.swift`:

```swift
import Testing
import Foundation
@testable import PTNetworking

@Suite("SSEParser")
struct SSEParserTests {
    @Test("Parses single data-only event")
    func singleDataEvent() async throws {
        let raw = "data: {\"text\":\"hello\"}\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "{\"text\":\"hello\"}")
        #expect(events[0].event == nil)
        #expect(events[0].id == nil)
    }

    @Test("Parses event with type and id")
    func eventWithTypeAndId() async throws {
        let raw = "event: message\nid: 42\ndata: payload\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].event == "message")
        #expect(events[0].id == "42")
        #expect(events[0].data == "payload")
    }

    @Test("Parses multi-line data (joined with newlines)")
    func multiLineData() async throws {
        let raw = "data: line1\ndata: line2\ndata: line3\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "line1\nline2\nline3")
    }

    @Test("Parses multiple events in stream")
    func multipleEvents() async throws {
        let raw = "data: first\n\ndata: second\n\ndata: third\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 3)
        #expect(events[0].data == "first")
        #expect(events[1].data == "second")
        #expect(events[2].data == "third")
    }

    @Test("Skips comment lines (colon prefix)")
    func skipsComments() async throws {
        let raw = ": this is a comment\ndata: actual\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "actual")
    }

    @Test("Handles [DONE] sentinel")
    func doneSignal() async throws {
        let raw = "data: {\"text\":\"hi\"}\n\ndata: [DONE]\n\n"
        let events = try await collectEvents(from: raw)
        // [DONE] should still be emitted as an event; consumer decides what to do
        #expect(events.count == 2)
        #expect(events[1].data == "[DONE]")
    }

    @Test("Handles retry field")
    func retryField() async throws {
        let raw = "retry: 5000\ndata: hello\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].retry == 5000)
        #expect(events[0].data == "hello")
    }

    @Test("Ignores lines without colon")
    func ignoresInvalidLines() async throws {
        let raw = "invalid line\ndata: valid\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "valid")
    }

    // MARK: - Helper

    private func collectEvents(from text: String) async throws -> [SSEEvent] {
        let lines = text.components(separatedBy: "\n")
        let stream = SSEParser.events(from: makeAsyncLines(lines))
        var events: [SSEEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func makeAsyncLines(_ lines: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTNetworking && swift test --filter SSEParserTests 2>&1 | tail -10`
Expected: FAIL — `SSEEvent` and `SSEParser` not found.

- [ ] **Step 3: Create SSEEvent**

Create `Packages/PTNetworking/Sources/PTNetworking/SSE/SSEEvent.swift`:

```swift
import Foundation

public struct SSEEvent: Sendable, Equatable {
    /// Event type (from `event:` field). Nil if not specified.
    public let event: String?
    /// Event payload (from `data:` field). Multiple data lines are joined with `\n`.
    public let data: String
    /// Last event ID (from `id:` field).
    public let id: String?
    /// Reconnection time in milliseconds (from `retry:` field).
    public let retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }

    /// Whether this event signals the end of the stream (OpenAI convention).
    public var isDone: Bool {
        data == "[DONE]"
    }
}
```

- [ ] **Step 4: Create SSEParser**

Create `Packages/PTNetworking/Sources/PTNetworking/SSE/SSEParser.swift`:

```swift
import Foundation

public enum SSEParser {
    /// Parse an `AsyncStream<String>` of lines into SSE events.
    ///
    /// Each line in the stream corresponds to one text line from the HTTP response.
    /// An empty line signals the end of an event (per the SSE spec).
    public static func events(from lines: AsyncStream<String>) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var eventType: String?
                var dataLines: [String] = []
                var eventId: String?
                var retry: Int?

                for await line in lines {
                    // Empty line = dispatch event
                    if line.isEmpty {
                        if !dataLines.isEmpty {
                            let event = SSEEvent(
                                event: eventType,
                                data: dataLines.joined(separator: "\n"),
                                id: eventId,
                                retry: retry
                            )
                            continuation.yield(event)
                        }
                        // Reset for next event
                        eventType = nil
                        dataLines = []
                        eventId = nil
                        retry = nil
                        continue
                    }

                    // Comment line (starts with colon)
                    if line.hasPrefix(":") {
                        continue
                    }

                    // Parse "field: value" or "field:value"
                    let field: String
                    let value: String
                    if let colonIndex = line.firstIndex(of: ":") {
                        field = String(line[line.startIndex..<colonIndex])
                        let afterColon = line.index(after: colonIndex)
                        if afterColon < line.endIndex && line[afterColon] == " " {
                            value = String(line[line.index(after: afterColon)...])
                        } else {
                            value = String(line[afterColon...])
                        }
                    } else {
                        // Lines without colon are ignored per SSE spec
                        continue
                    }

                    switch field {
                    case "event":
                        eventType = value
                    case "data":
                        dataLines.append(value)
                    case "id":
                        eventId = value
                    case "retry":
                        retry = Int(value)
                    default:
                        break // Unknown fields are ignored
                    }
                }

                // Flush any remaining event if stream ends without trailing blank line
                if !dataLines.isEmpty {
                    let event = SSEEvent(
                        event: eventType,
                        data: dataLines.joined(separator: "\n"),
                        id: eventId,
                        retry: retry
                    )
                    continuation.yield(event)
                }

                continuation.finish()
            }
        }
    }

    /// Convenience: parse `URLSession.AsyncBytes` into SSE events.
    ///
    /// This converts the byte stream into lines first, then parses SSE events.
    /// Includes a 15-second heartbeat timeout to detect proxy disconnections.
    public static func events(from bytes: URLSession.AsyncBytes, heartbeatTimeout: TimeInterval = 15) -> AsyncThrowingStream<SSEEvent, Error> {
        let lines = AsyncStream<String> { continuation in
            Task {
                var buffer = ""
                for try await byte in bytes {
                    let char = Character(UnicodeScalar(byte))
                    if char == "\n" {
                        continuation.yield(buffer)
                        buffer = ""
                    } else if char != "\r" {
                        buffer.append(char)
                    }
                }
                // Yield any remaining buffer content
                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
        }
        return events(from: lines)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd Packages/PTNetworking && swift test --filter SSEParserTests 2>&1 | tail -15`
Expected: All 8 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/SSE/SSEEvent.swift Packages/PTNetworking/Sources/PTNetworking/SSE/SSEParser.swift Packages/PTNetworking/Tests/PTNetworkingTests/SSE/SSEParserTests.swift
git commit -m "feat(PTNetworking): add SSEEvent and SSEParser with line-based async parsing"
```

---

### Task 6: RemoteFile and WebDAVAuth

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/WebDAV/RemoteFile.swift`
- Create: `Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVAuth.swift`

- [ ] **Step 1: Create RemoteFile model**

Create `Packages/PTNetworking/Sources/PTNetworking/WebDAV/RemoteFile.swift`:

```swift
import Foundation

/// Metadata for a file or directory on a WebDAV server.
public struct RemoteFile: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let mimeType: String?
    public let size: Int?
    public let eTag: String?
    public let creationDate: Date?
    public let modifiedDate: Date?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        mimeType: String? = nil,
        size: Int? = nil,
        eTag: String? = nil,
        creationDate: Date? = nil,
        modifiedDate: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.mimeType = mimeType
        self.size = size
        self.eTag = eTag
        self.creationDate = creationDate
        self.modifiedDate = modifiedDate
    }
}
```

- [ ] **Step 2: Create WebDAVAuth**

Create `Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVAuth.swift`:

```swift
import Foundation

/// Authentication method for WebDAV connections.
public enum WebDAVAuth: Sendable {
    case basic(user: String, password: String)

    /// Returns the `Authorization` header value.
    func authorizationHeader() -> String {
        switch self {
        case .basic(let user, let password):
            let credentials = "\(user):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            return "Basic \(encoded)"
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/WebDAV/RemoteFile.swift Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVAuth.swift
git commit -m "feat(PTNetworking): add RemoteFile model and WebDAVAuth"
```

---

### Task 7: WebDAVClient

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVClient.swift`
- Test: `Packages/PTNetworking/Tests/PTNetworkingTests/WebDAV/WebDAVClientTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/WebDAV/WebDAVClientTests.swift`:

```swift
import Testing
import Foundation
@testable import PTNetworking

@Suite("WebDAVClient")
struct WebDAVClientTests {
    @Test("Parses PROPFIND multistatus XML response")
    func parsePropfindXML() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/paper_reader/</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>paper_reader</D:displayname>
                <D:resourcetype><D:collection/></D:resourcetype>
                <D:getcontentlength>0</D:getcontentlength>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/paper_reader/settings.json</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>settings.json</D:displayname>
                <D:resourcetype/>
                <D:getcontentlength>1234</D:getcontentlength>
                <D:getcontenttype>application/json</D:getcontenttype>
                <D:getetag>"abc123"</D:getetag>
                <D:getlastmodified>Thu, 03 Apr 2026 12:00:00 GMT</D:getlastmodified>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let files = WebDAVXMLParser.parseMultistatus(xml.data(using: .utf8)!)
        #expect(files.count == 2)

        let dir = files[0]
        #expect(dir.name == "paper_reader")
        #expect(dir.isDirectory == true)

        let file = files[1]
        #expect(file.name == "settings.json")
        #expect(file.isDirectory == false)
        #expect(file.size == 1234)
        #expect(file.mimeType == "application/json")
        #expect(file.eTag == "\"abc123\"")
    }

    @Test("Basic auth header is correctly generated")
    func basicAuthHeader() {
        let auth = WebDAVAuth.basic(user: "admin", password: "secret")
        let header = auth.authorizationHeader()
        let expected = "Basic " + Data("admin:secret".utf8).base64EncodedString()
        #expect(header == expected)
    }

    @Test("URL path encoding handles spaces")
    func pathEncoding() {
        let encoded = WebDAVClient.encodePath("/paper reader/my file.epub")
        #expect(encoded == "/paper%20reader/my%20file.epub")
        #expect(!encoded.contains(" "))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTNetworking && swift test --filter WebDAVClientTests 2>&1 | tail -10`
Expected: FAIL — `WebDAVXMLParser`, `WebDAVClient` not found.

- [ ] **Step 3: Implement WebDAVClient**

Create `Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVClient.swift`:

```swift
import Foundation

/// WebDAV client for file synchronization (replaces Flutter's webdav_client package).
public actor WebDAVClient {
    private let baseURL: URL
    private let auth: WebDAVAuth
    private let session: URLSession

    public init(baseURL: URL, auth: WebDAVAuth, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Public API

    /// List files in a directory (PROPFIND depth 1).
    public func listDirectory(_ path: String) async throws -> [RemoteFile] {
        let url = baseURL.appendingPathComponent(Self.encodePath(path))
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propfindBody.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try Self.checkMultistatusResponse(response)
        return WebDAVXMLParser.parseMultistatus(data)
    }

    /// Get file data.
    public func get(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(Self.encodePath(path))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Self.checkResponse(response)
        return data
    }

    /// Upload file data.
    public func put(_ path: String, data: Data) async throws {
        let url = baseURL.appendingPathComponent(Self.encodePath(path))
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        try Self.checkResponse(response)
    }

    /// Delete a file or directory.
    public func delete(_ path: String) async throws {
        let url = baseURL.appendingPathComponent(Self.encodePath(path))
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        try Self.checkResponse(response)
    }

    /// Create a directory (MKCOL).
    public func mkcol(_ path: String) async throws {
        let url = baseURL.appendingPathComponent(Self.encodePath(path))
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        try Self.checkResponse(response)
    }

    /// Create directory path recursively.
    public func mkdirAll(_ path: String) async throws {
        let components = path.split(separator: "/").map(String.init)
        var current = ""
        for component in components {
            current += "/\(component)"
            do {
                try await mkcol(current)
            } catch NetworkError.httpError(let code, _) where code == 405 || code == 301 {
                // 405 = already exists, 301 = redirect (already exists)
                continue
            }
        }
    }

    /// Check if a path exists.
    public func exists(_ path: String) async -> Bool {
        do {
            let url = baseURL.appendingPathComponent(Self.encodePath(path))
            var request = URLRequest(url: url)
            request.httpMethod = "PROPFIND"
            request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
            request.setValue("0", forHTTPHeaderField: "Depth")
            request.httpBody = Self.propfindBody.data(using: .utf8)

            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(statusCode) || statusCode == 207
        } catch {
            return false
        }
    }

    /// Test connection (ping).
    public func ping() async throws {
        let url = baseURL.appendingPathComponent("/")
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(auth.authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.httpBody = Self.propfindBody.data(using: .utf8)
        request.timeoutInterval = 8

        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<400).contains(statusCode) || statusCode == 207 else {
            throw NetworkError.httpError(statusCode: statusCode, data: nil)
        }
    }

    // MARK: - Internal

    /// Encode a path for use in URLs, preserving forward slashes.
    public nonisolated static func encodePath(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
      <D:allprop/>
    </D:propfind>
    """

    private static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError(statusCode: http.statusCode, data: nil)
        }
    }

    private static func checkMultistatusResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }
        guard http.statusCode == 207 || (200..<300).contains(http.statusCode) else {
            throw NetworkError.httpError(statusCode: http.statusCode, data: nil)
        }
    }
}

// MARK: - XML Parser for PROPFIND responses

public enum WebDAVXMLParser {
    /// Parse a `multistatus` XML response into `RemoteFile` entries.
    public static func parseMultistatus(_ data: Data) -> [RemoteFile] {
        let delegate = PropfindXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.files
    }
}

// MARK: - XMLParser Delegate

private final class PropfindXMLDelegate: NSObject, XMLParserDelegate {
    var files: [RemoteFile] = []

    private var currentElement = ""
    private var currentText = ""

    // Per-response state
    private var href = ""
    private var displayName = ""
    private var isCollection = false
    private var contentLength: Int?
    private var contentType: String?
    private var eTag: String?
    private var lastModified: String?
    private var inResponse = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = local
        currentText = ""

        if local == "response" {
            inResponse = true
            href = ""
            displayName = ""
            isCollection = false
            contentLength = nil
            contentType = nil
            eTag = nil
            lastModified = nil
        } else if local == "collection" && inResponse {
            isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inResponse {
            switch local {
            case "href":
                href = trimmed
            case "displayname":
                displayName = trimmed
            case "getcontentlength":
                contentLength = Int(trimmed)
            case "getcontenttype":
                contentType = trimmed
            case "getetag":
                eTag = trimmed
            case "getlastmodified":
                lastModified = trimmed
            case "response":
                let name = displayName.isEmpty
                    ? (href as NSString).lastPathComponent
                    : displayName
                let modified = lastModified.flatMap { Self.parseHTTPDate($0) }
                let file = RemoteFile(
                    path: href,
                    name: name,
                    isDirectory: isCollection,
                    mimeType: contentType,
                    size: contentLength,
                    eTag: eTag,
                    creationDate: nil,
                    modifiedDate: modified
                )
                files.append(file)
                inResponse = false
            default:
                break
            }
        }
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private static func parseHTTPDate(_ string: String) -> Date? {
        httpDateFormatter.date(from: string)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PTNetworking && swift test --filter WebDAVClientTests 2>&1 | tail -15`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/WebDAV/WebDAVClient.swift Packages/PTNetworking/Tests/PTNetworkingTests/WebDAV/WebDAVClientTests.swift
git commit -m "feat(PTNetworking): add WebDAVClient with PROPFIND XML parsing"
```

---

### Task 8: PaperTok Models

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokModels.swift`
- Test: `Packages/PTNetworking/Tests/PTNetworkingTests/PaperTok/PaperTokModelsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Packages/PTNetworking/Tests/PTNetworkingTests/PaperTok/PaperTokModelsTests.swift`:

```swift
import Testing
import Foundation
@testable import PTNetworking

@Suite("PaperTokModels")
struct PaperTokModelsTests {
    @Test("Decodes PaperTokCard from API JSON")
    func decodesCard() throws {
        let json = """
        {
          "pageid": 12345,
          "title": "Attention Is All You Need",
          "displaytitle": "Attention Is All You Need",
          "extract": "A groundbreaking paper on transformer architecture",
          "day": "2026-04-01",
          "thumbnail": {"source": "https://example.com/thumb.jpg", "width": 200, "height": 150},
          "thumbnails": ["https://example.com/img1.jpg", "https://example.com/img2.jpg"],
          "url": "https://arxiv.org/abs/1706.03762"
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.id == 12345)
        #expect(card.title == "Attention Is All You Need")
        #expect(card.displayTitle == "Attention Is All You Need")
        #expect(card.extract == "A groundbreaking paper on transformer architecture")
        #expect(card.day == "2026-04-01")
        #expect(card.thumbnailURL == "https://example.com/thumb.jpg")
        #expect(card.thumbnails == ["https://example.com/img1.jpg", "https://example.com/img2.jpg"])
        #expect(card.url == "https://arxiv.org/abs/1706.03762")
    }

    @Test("PaperTokCard bestTitle prefers displayTitle")
    func bestTitle() throws {
        let json = """
        {"pageid": 1, "title": "raw", "displaytitle": "Display Title", "extract": "x"}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.bestTitle == "Display Title")
    }

    @Test("PaperTokCard bestTitle falls back to title")
    func bestTitleFallback() throws {
        let json = """
        {"pageid": 1, "title": "Fallback", "extract": "x"}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.bestTitle == "Fallback")
    }

    @Test("Decodes PaperTokDetail from API JSON")
    func decodesDetail() throws {
        let json = """
        {
          "id": 42,
          "title": "BERT",
          "display_title": "BERT: Pre-training",
          "external_id": "arxiv-1810.04805",
          "url": "https://arxiv.org/abs/1810.04805",
          "one_liner": "A language model",
          "content_explain": "Detailed explanation here",
          "pdf_url": "https://arxiv.org/pdf/1810.04805.pdf",
          "epub_url": "https://papertok.ai/epub/42.epub",
          "epub_url_en": "https://papertok.ai/epub/42_en.epub",
          "epub_url_zh": "https://papertok.ai/epub/42_zh.epub",
          "epub_url_bilingual": null,
          "images": ["https://example.com/fig1.png"],
          "generated_images": [
            {"url": "https://example.com/gen1.png", "provider": "seedream", "lang": "en"}
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.id == 42)
        #expect(detail.title == "BERT")
        #expect(detail.displayTitle == "BERT: Pre-training")
        #expect(detail.pdfUrl == "https://arxiv.org/pdf/1810.04805.pdf")
        #expect(detail.images == ["https://example.com/fig1.png"])
        #expect(detail.generatedImages.count == 1)
        #expect(detail.generatedImages[0].provider == "seedream")
    }

    @Test("PaperTokDetail bestEpubUrl priority")
    func bestEpubUrl() throws {
        let json = """
        {
          "id": 1, "title": "T",
          "epub_url": "https://a.com/main.epub",
          "epub_url_zh": "https://a.com/zh.epub",
          "epub_url_en": "https://a.com/en.epub"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.bestEpubUrl == "https://a.com/main.epub")
    }

    @Test("PaperTokDetail carouselImages prefers generated")
    func carouselImages() throws {
        let json = """
        {
          "id": 1, "title": "T",
          "images": ["https://a.com/static.png"],
          "generated_images": [
            {"url": "https://a.com/gen.png", "provider": "p"}
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.carouselImages == ["https://a.com/gen.png"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/PTNetworking && swift test --filter PaperTokModelsTests 2>&1 | tail -10`
Expected: FAIL — `PaperTokCard`, `PaperTokDetail` not found.

- [ ] **Step 3: Implement PaperTok models**

Create `Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokModels.swift`:

```swift
import Foundation

// MARK: - PaperTokCard

/// A paper card from the PaperTok feed API (`/api/papers/random`).
public struct PaperTokCard: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let displayTitle: String?
    public let extract: String
    public let day: String?
    public let thumbnail: Thumbnail?
    public let thumbnails: [String]
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case id = "pageid"
        case title
        case displayTitle = "displaytitle"
        case extract
        case day
        case thumbnail
        case thumbnails
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        extract = try container.decodeIfPresent(String.self, forKey: .extract) ?? ""
        day = try container.decodeIfPresent(String.self, forKey: .day)
        thumbnail = try container.decodeIfPresent(Thumbnail.self, forKey: .thumbnail)
        thumbnails = try container.decodeIfPresent([String].self, forKey: .thumbnails) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    /// The best display title — prefers displayTitle, falls back to title.
    public var bestTitle: String {
        if let dt = displayTitle, !dt.trimmingCharacters(in: .whitespaces).isEmpty {
            return dt
        }
        return title
    }

    /// The thumbnail source URL string.
    public var thumbnailURL: String? {
        thumbnail?.source
    }

    public struct Thumbnail: Codable, Sendable, Equatable {
        public let source: String?
        public let width: Int?
        public let height: Int?
    }
}

// MARK: - PaperTokDetail

/// Full detail of a paper from the PaperTok detail API (`/api/papers/:id`).
public struct PaperTokDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let displayTitle: String?
    public let externalId: String?
    public let url: String?
    public let oneLiner: String?
    public let contentExplain: String?
    public let pdfUrl: String?
    public let pdfLocalUrl: String?
    public let epubUrl: String?
    public let epubUrlEn: String?
    public let epubUrlZh: String?
    public let epubUrlBilingual: String?
    public let images: [String]
    public let generatedImages: [PaperTokGeneratedImage]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        oneLiner = try container.decodeIfPresent(String.self, forKey: .oneLiner)
        contentExplain = try container.decodeIfPresent(String.self, forKey: .contentExplain)
        pdfUrl = try container.decodeIfPresent(String.self, forKey: .pdfUrl)
        pdfLocalUrl = try container.decodeIfPresent(String.self, forKey: .pdfLocalUrl)
        epubUrl = try container.decodeIfPresent(String.self, forKey: .epubUrl)
        epubUrlEn = try container.decodeIfPresent(String.self, forKey: .epubUrlEn)
        epubUrlZh = try container.decodeIfPresent(String.self, forKey: .epubUrlZh)
        epubUrlBilingual = try container.decodeIfPresent(String.self, forKey: .epubUrlBilingual)
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
        generatedImages = try container.decodeIfPresent([PaperTokGeneratedImage].self, forKey: .generatedImages) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, displayTitle, externalId, url, oneLiner, contentExplain
        case pdfUrl, pdfLocalUrl, epubUrl, epubUrlEn, epubUrlZh, epubUrlBilingual
        case images, generatedImages
    }

    /// Best EPUB URL — prefers primary, then zh, en, bilingual.
    public var bestEpubUrl: String? {
        [epubUrl, epubUrlZh, epubUrlEn, epubUrlBilingual]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Images for the detail carousel — prefers generated images over static.
    public var carouselImages: [String] {
        let gen = generatedImages.map(\.url).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return gen.isEmpty ? images : gen
    }
}

// MARK: - PaperTokGeneratedImage

public struct PaperTokGeneratedImage: Codable, Sendable, Equatable {
    public let url: String
    public let provider: String?
    public let lang: String?
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/PTNetworking && swift test --filter PaperTokModelsTests 2>&1 | tail -15`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokModels.swift Packages/PTNetworking/Tests/PTNetworkingTests/PaperTok/PaperTokModelsTests.swift
git commit -m "feat(PTNetworking): add PaperTokCard, PaperTokDetail models with JSON decoding"
```

---

### Task 9: PaperTokAPI Client

**Files:**
- Create: `Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokAPI.swift`

- [ ] **Step 1: Implement PaperTokAPI**

Create `Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokAPI.swift`:

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokAPI.swift
git commit -m "feat(PTNetworking): add PaperTokAPI REST client"
```

---

### Task 10: Run Full Test Suite and Final Commit

**Files:**
- None new — verification only.

- [ ] **Step 1: Run all PTNetworking tests**

Run:
```bash
cd Packages/PTNetworking && swift test 2>&1 | tail -30
```
Expected: All tests pass (import test + endpoint tests + network client tests + SSE tests + WebDAV tests + PaperTok model tests).

- [ ] **Step 2: Run PTCore tests to verify no regression**

Run:
```bash
cd Packages/PTCore && swift test 2>&1 | tail -15
```
Expected: All 38 PTCore tests still pass.

- [ ] **Step 3: Push to remote**

```bash
git push origin swift-native
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Package.swift + module entry | 1 import test |
| 2 | HTTPMethod + Endpoint | 5 tests (URL, headers, body, timeout) |
| 3 | NetworkError | 0 (tested via NetworkClient) |
| 4 | NetworkClient | 4 tests (JSON, raw, 404, decode error) |
| 5 | SSEEvent + SSEParser | 8 tests (single, multi-line, multi-event, comments, retry) |
| 6 | RemoteFile + WebDAVAuth | 0 (tested via WebDAVClient) |
| 7 | WebDAVClient + XML parser | 3 tests (XML parsing, auth header, path encoding) |
| 8 | PaperTokModels | 6 tests (card decode, bestTitle, detail decode, bestEpub, carousel) |
| 9 | PaperTokAPI client | 0 (integration; models tested above) |
| 10 | Full suite verification | Run all tests |

**Total: 10 tasks, ~27 new tests**
