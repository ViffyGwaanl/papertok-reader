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

@Suite("NetworkClient", .serialized)
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
        struct Item: Decodable, Sendable, Equatable { let name: String; let count: Int }
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
            struct Item: Decodable, Sendable { let id: Int }
            let _: Item = try await client.request(endpoint)
        }
    }
}
