import Foundation
import PTReader

public enum ReaderImageFileStore {
    public static func temporaryFileURL(for asset: ReaderImageAsset) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("papertok-reader-images", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(asset.filename)
        try asset.data.write(to: url, options: .atomic)
        return url
    }
}
