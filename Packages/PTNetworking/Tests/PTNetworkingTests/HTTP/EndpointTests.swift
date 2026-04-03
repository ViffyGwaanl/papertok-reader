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
        struct Payload: Encodable, Sendable {
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
