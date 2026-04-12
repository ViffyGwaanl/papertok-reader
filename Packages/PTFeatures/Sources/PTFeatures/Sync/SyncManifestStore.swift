import Foundation
import PTCore
import PTNetworking

/// Represents the difference between a local and a remote manifest. Tells the
/// sync engine which entities to upload, download, or resolve as conflicts.
public struct SyncDelta: Sendable, Equatable {
    public var uploadEntities: [String]
    public var downloadEntities: [String]
    public var conflicts: [String]

    public init(
        uploadEntities: [String] = [],
        downloadEntities: [String] = [],
        conflicts: [String] = []
    ) {
        self.uploadEntities = uploadEntities
        self.downloadEntities = downloadEntities
        self.conflicts = conflicts
    }

    public var isEmpty: Bool {
        uploadEntities.isEmpty && downloadEntities.isEmpty && conflicts.isEmpty
    }
}

/// Persists and fetches the `SyncManifest`, both locally (in the app group
/// container) and remotely on a WebDAV share. It is the single source of truth
/// for what has been synced and when.
public actor SyncManifestStore {
    /// Remote filename for the manifest (lives at `remoteFolder/manifest.json`).
    public static let manifestFilename = "manifest.json"

    private let fileManager: FileManager
    private let localURL: URL

    public init(
        fileManager: FileManager = .default,
        localURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let localURL {
            self.localURL = localURL
        } else {
            let container = AppConfig.appGroupContainerURL(fileManager: fileManager)
            self.localURL = container
                .appendingPathComponent("Sync", isDirectory: true)
                .appendingPathComponent("manifest.json")
        }
    }

    // MARK: - Local

    /// Load the manifest from disk, returning `.empty` if nothing is stored yet.
    public func loadLocalManifest() async -> SyncManifest {
        guard fileManager.fileExists(atPath: localURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: localURL)
            return try Self.decoder.decode(SyncManifest.self, from: data)
        } catch {
            return .empty
        }
    }

    /// Persist the manifest to disk.
    public func saveLocalManifest(_ manifest: SyncManifest) async throws {
        let parent = localURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = try Self.encoder.encode(manifest)
        try data.write(to: localURL, options: .atomic)
    }

    // MARK: - Remote

    /// Download and decode the manifest at `<remoteFolder>/manifest.json`.
    /// Returns `nil` if the file does not exist yet.
    public func loadRemoteManifest(
        webdav: WebDAVClient,
        remoteFolder: String
    ) async throws -> SyncManifest? {
        let path = Self.remotePath(folder: remoteFolder)
        guard await webdav.exists(path) else { return nil }
        let data = try await webdav.get(path)
        return try Self.decoder.decode(SyncManifest.self, from: data)
    }

    /// Upload the manifest to `<remoteFolder>/manifest.json`.
    public func saveRemoteManifest(
        _ manifest: SyncManifest,
        webdav: WebDAVClient,
        remoteFolder: String
    ) async throws {
        try await webdav.mkdirAll(remoteFolder)
        let data = try Self.encoder.encode(manifest)
        try await webdav.put(Self.remotePath(folder: remoteFolder), data: data)
    }

    // MARK: - Delta computation

    /// Compare two manifests and return the entities that need uploading,
    /// downloading, or conflict resolution. An entity is considered a
    /// conflict when both sides have advanced past the other's last known
    /// state (i.e. local date > remote date AND remote date > local date is
    /// impossible, so we treat "both newer than last sync" as conflict).
    public nonisolated func computeDelta(
        local: SyncManifest,
        remote: SyncManifest
    ) -> SyncDelta {
        var uploads: [String] = []
        var downloads: [String] = []
        var conflicts: [String] = []

        let allKeys = Set(local.entityVersions.keys).union(remote.entityVersions.keys)
        let lastSync = local.lastSyncDate

        for key in allKeys.sorted() {
            let localDate = local.entityVersions[key]
            let remoteDate = remote.entityVersions[key]

            switch (localDate, remoteDate) {
            case (nil, nil):
                continue
            case (.some, nil):
                uploads.append(key)
            case (nil, .some):
                downloads.append(key)
            case let (.some(l), .some(r)):
                if l == r { continue }
                if let lastSync {
                    let localChanged = l > lastSync
                    let remoteChanged = r > lastSync
                    if localChanged && remoteChanged {
                        conflicts.append(key)
                    } else if localChanged {
                        uploads.append(key)
                    } else if remoteChanged {
                        downloads.append(key)
                    } else {
                        // Neither has advanced past last sync but they differ —
                        // favour the newer of the two.
                        if l > r { uploads.append(key) } else { downloads.append(key) }
                    }
                } else {
                    // No last-sync baseline: any divergence is a conflict.
                    conflicts.append(key)
                }
            }
        }

        return SyncDelta(
            uploadEntities: uploads,
            downloadEntities: downloads,
            conflicts: conflicts
        )
    }

    // MARK: - Helpers

    private static func remotePath(folder: String) -> String {
        let trimmed = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return "\(trimmed)/\(manifestFilename)"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
