import Foundation

public struct ReaderImageAsset: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let data: Data
    public let mimeType: String
    public let title: String?
    public let altText: String?
    public let sourceURL: String?

    public init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String,
        title: String? = nil,
        altText: String? = nil,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.altText = altText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sourceURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var filename: String {
        "reader-image.\(fileExtension)"
    }

    public var fileExtension: String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            "jpg"
        case "image/gif":
            "gif"
        case "image/webp":
            "webp"
        default:
            "png"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
