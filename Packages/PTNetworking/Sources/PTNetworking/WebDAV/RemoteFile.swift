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
