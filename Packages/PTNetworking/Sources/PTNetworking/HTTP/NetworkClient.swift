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
