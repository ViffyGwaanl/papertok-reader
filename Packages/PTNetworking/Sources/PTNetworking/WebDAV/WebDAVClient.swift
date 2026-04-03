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
    public static func parseMultistatus(_ data: Data) -> [RemoteFile] {
        let delegate = PropfindXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.files
    }
}

private final class PropfindXMLDelegate: NSObject, XMLParserDelegate {
    var files: [RemoteFile] = []

    private var currentElement = ""
    private var currentText = ""

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
            case "href": href = trimmed
            case "displayname": displayName = trimmed
            case "getcontentlength": contentLength = Int(trimmed)
            case "getcontenttype": contentType = trimmed
            case "getetag": eTag = trimmed
            case "getlastmodified": lastModified = trimmed
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
            default: break
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
