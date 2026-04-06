import Foundation
import ReadiumShared
import ReadiumStreamer

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
}

public enum EPUBOpenError: Error, LocalizedError {
    case invalidURL(String)
    case assetError(String)
    case streamerError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid file URL: \(url)"
        case .assetError(let msg):
            return "EPUB asset retrieval failed: \(msg)"
        case .streamerError(let msg):
            return "EPUB open failed: \(msg)"
        }
    }
}
