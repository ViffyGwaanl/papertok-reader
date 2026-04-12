import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("ReaderImageFileStore")
struct ReaderImageFileStoreTests {
    @Test("temporaryFileURL writes image data using the asset filename")
    func temporaryFileURLWritesImageData() throws {
        let asset = ReaderImageAsset(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png"
        )

        let url = try ReaderImageFileStore.temporaryFileURL(for: asset)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == asset.filename)
        #expect(try Data(contentsOf: url) == asset.data)
    }
}
