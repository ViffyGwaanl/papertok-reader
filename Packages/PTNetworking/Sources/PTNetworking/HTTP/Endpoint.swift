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
