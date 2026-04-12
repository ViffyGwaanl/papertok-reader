import Foundation

public actor NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        configuration: URLSessionConfiguration = .default,
        decoder: JSONDecoder = NetworkClient.makeDefaultDecoder()
    ) {
        self.session = URLSession(configuration: configuration)
        self.decoder = decoder
    }

    public static func makeDefaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Self.apiTimestampFormatter.date(from: value)
                ?? Self.iso8601WithFractionalSeconds.date(from: value)
                ?? Self.iso8601.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string: \(value)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let apiTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
