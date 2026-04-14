#if canImport(ReadiumShared) && canImport(ReadiumStreamer)
import Foundation
import PTCore
import ReadiumShared
import ReadiumStreamer

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct EPUBImportMetadata: Sendable, Equatable {
    public let title: String
    public let author: String
    public let coverPNGData: Data?

    public init(title: String, author: String, coverPNGData: Data?) {
        self.title = title
        self.author = author
        self.coverPNGData = coverPNGData
    }
}

/// Opens an .epub file from disk and returns a Readium Publication.
///
/// Uses `PublicationOpener` with the default `EPUBParser` to parse EPUB files.
/// The `AssetRetriever` is used to load the file as a Readium `Asset`.
public final class EPUBPublicationOpener: @unchecked Sendable {
    private let assetRetriever: AssetRetriever
    private let publicationOpener: PublicationOpener

    public init() {
        let httpClient = DefaultHTTPClient()
        self.assetRetriever = AssetRetriever(httpClient: httpClient)
        let parser = EPUBParser()
        self.publicationOpener = PublicationOpener(parser: parser)
    }

    /// Open an EPUB file at the given URL.
    /// - Returns: A ready-to-use `Publication`.
    /// - Throws: `EPUBOpenError` if the file cannot be opened.
    public func open(at url: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: url) else {
            throw EPUBOpenError.invalidURL(url.absoluteString)
        }

        let assetResult = await assetRetriever.retrieve(url: fileURL)
        let asset: Asset
        switch assetResult {
        case .success(let a):
            asset = a
        case .failure(let error):
            throw EPUBOpenError.assetError(String(describing: error))
        }

        let pubResult = await publicationOpener.open(
            asset: asset,
            allowUserInteraction: false
        )
        switch pubResult {
        case .success(let pub):
            return pub
        case .failure(let error):
            throw EPUBOpenError.streamerError(String(describing: error))
        }
    }

    public func readImportMetadata(at url: URL, fallbackTitle: String? = nil) async throws -> EPUBImportMetadata {
        let publication = try await open(at: url)
        let rawTitle = publication.manifest.metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAuthor = publication.manifest.metadata.authors.first?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)

#if canImport(UIKit)
        let coverImage = try await publication.cover().get()
        let coverPNGData = coverImage?.pngData()
#elseif canImport(AppKit)
        let coverPNGData: Data? = nil
#else
        let coverPNGData: Data? = nil
#endif

        return EPUBImportMetadata(
            title: (rawTitle?.isEmpty ?? true) ? (fallbackTitle ?? "") : rawTitle!,
            author: rawAuthor ?? "",
            coverPNGData: coverPNGData
        )
    }
}

public enum EPUBOpenError: Error, LocalizedError {
    case invalidURL(String)
    case assetError(String)
    case streamerError(String)
    case searchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL, .assetError, .streamerError:
            return AppLocalization.string(
                "errors.reader.cannot_open",
                value: "Couldn't open this book."
            )
        case .searchFailed:
            return AppLocalization.string(
                "errors.reader.search_failed",
                value: "Couldn't search this book."
            )
        }
    }

    public var failureReason: String? {
        switch self {
        case .invalidURL(let detail),
             .assetError(let detail),
             .streamerError(let detail),
             .searchFailed(let detail):
            return detail
        }
    }
}
#endif
