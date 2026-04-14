import Foundation
import PTCore
import PTNetworking

/// The phase the sync engine is currently in.
public enum SyncPhase: String, Sendable {
    case preparing
    case computingDelta
    case uploading
    case downloading
    case resolving
    case finalizing
    case done
}

/// Progress reporting structure, emitted via the progress callback.
public struct SyncProgress: Sendable {
    public var phase: SyncPhase
    public var currentItem: String?
    public var total: Int
    public var completed: Int

    public init(
        phase: SyncPhase,
        currentItem: String? = nil,
        total: Int = 0,
        completed: Int = 0
    ) {
        self.phase = phase
        self.currentItem = currentItem
        self.total = total
        self.completed = completed
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

/// Summary returned after a sync pass.
public struct SyncResult: Sendable {
    public var uploaded: Int
    public var downloaded: Int
    public var conflictsResolved: Int
    public var errors: [String]

    public init(
        uploaded: Int = 0,
        downloaded: Int = 0,
        conflictsResolved: Int = 0,
        errors: [String] = []
    ) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.conflictsResolved = conflictsResolved
        self.errors = errors
    }
}

/// Describes a single entity root that the engine knows how to upload and
/// download. Generally maps an entity key (e.g. `"books"`) to a local
/// directory and a remote path.
public struct SyncFileRoot: Sendable {
    public let entityKey: String
    public let localDirectory: URL
    public let remotePath: String

    public init(entityKey: String, localDirectory: URL, remotePath: String) {
        self.entityKey = entityKey
        self.localDirectory = localDirectory
        self.remotePath = remotePath
    }
}

/// Errors thrown by the incremental sync engine.
public enum IncrementalSyncError: Error, LocalizedError, Sendable {
    case unknownEntity(String)
    case conflictRequiresUserInput(String)

    public var errorDescription: String? {
        switch self {
        case .unknownEntity(let key):
            return AppLocalization.format("errors.sync.unknown_entity_format", locale: .autoupdatingCurrent,
                key
            )
        case .conflictRequiresUserInput(let key):
            return AppLocalization.format("errors.sync.manual_conflict_required_format", locale: .autoupdatingCurrent,
                key
            )
        }
    }
}

/// The main orchestrator for delta-based bidirectional WebDAV sync. Replaces
/// the monolithic `WebDAVSyncService.sync()` approach with a manifest-driven
/// engine that only transfers what changed.
public actor IncrementalSyncEngine {
    private let webdavClient: WebDAVClient
    private let manifestStore: SyncManifestStore
    private let conflictResolver: ConflictResolver
    private let fileRoots: [String: SyncFileRoot]
    private let remoteFolder: String
    private let fileManager: FileManager

    public init(
        webdavClient: WebDAVClient,
        manifestStore: SyncManifestStore,
        conflictResolver: ConflictResolver,
        fileRoots: [SyncFileRoot],
        remoteFolder: String = "/PaperTok",
        fileManager: FileManager = .default
    ) {
        self.webdavClient = webdavClient
        self.manifestStore = manifestStore
        self.conflictResolver = conflictResolver
        self.fileRoots = Dictionary(uniqueKeysWithValues: fileRoots.map { ($0.entityKey, $0) })
        self.remoteFolder = remoteFolder
        self.fileManager = fileManager
    }

    /// Run a full delta-based sync pass. The optional callback is invoked
    /// on each progress step; it runs on the caller's executor.
    public func sync(
        progressCallback: (@Sendable (SyncProgress) -> Void)? = nil
    ) async throws -> SyncResult {
        var result = SyncResult()

        report(progressCallback, SyncProgress(phase: .preparing))

        // 1. Ensure remote folder exists
        try await webdavClient.mkdirAll(remoteFolder)

        // 2. Load manifests
        var local = await manifestStore.loadLocalManifest()
        let remote = (try? await manifestStore.loadRemoteManifest(
            webdav: webdavClient,
            remoteFolder: remoteFolder
        )) ?? SyncManifest.empty

        // 3. Compute delta
        report(progressCallback, SyncProgress(phase: .computingDelta))
        let delta = manifestStore.computeDelta(local: local, remote: remote)

        let totalWork = delta.uploadEntities.count
            + delta.downloadEntities.count
            + delta.conflicts.count

        // 4. Uploads
        var completed = 0
        for key in delta.uploadEntities {
            report(progressCallback, SyncProgress(
                phase: .uploading,
                currentItem: key,
                total: totalWork,
                completed: completed
            ))
            do {
                try await uploadEntity(key)
                local.markEntitySynced(key)
                result.uploaded += 1
            } catch {
                result.errors.append("upload \(key): \(error.localizedDescription)")
            }
            completed += 1
        }

        // 5. Downloads
        for key in delta.downloadEntities {
            report(progressCallback, SyncProgress(
                phase: .downloading,
                currentItem: key,
                total: totalWork,
                completed: completed
            ))
            do {
                try await downloadEntity(key)
                if let remoteDate = remote.entityVersions[key] {
                    local.entityVersions[key] = remoteDate
                }
                result.downloaded += 1
            } catch {
                result.errors.append("download \(key): \(error.localizedDescription)")
            }
            completed += 1
        }

        // 6. Conflict resolution
        for key in delta.conflicts {
            report(progressCallback, SyncProgress(
                phase: .resolving,
                currentItem: key,
                total: totalWork,
                completed: completed
            ))
            let localDate = local.entityVersions[key] ?? .distantPast
            let remoteDate = remote.entityVersions[key] ?? .distantPast
            let resolution = await conflictResolver.resolve(
                entityKey: key,
                local: key,
                localDate: localDate,
                remote: key,
                remoteDate: remoteDate
            )
            do {
                switch resolution {
                case .useLocal:
                    try await uploadEntity(key)
                    local.markEntitySynced(key)
                case .useRemote:
                    try await downloadEntity(key)
                    local.entityVersions[key] = remoteDate
                case .merge:
                    // Callers that want custom merges should pre-compute
                    // them; in the default path we behave like useLocal.
                    try await uploadEntity(key)
                    local.markEntitySynced(key)
                case .askUser:
                    throw IncrementalSyncError.conflictRequiresUserInput(key)
                }
                result.conflictsResolved += 1
            } catch {
                result.errors.append("conflict \(key): \(error.localizedDescription)")
            }
            completed += 1
        }

        // 7. Finalise manifest
        report(progressCallback, SyncProgress(phase: .finalizing))
        local.markSyncCompleted()
        try await manifestStore.saveLocalManifest(local)
        try await manifestStore.saveRemoteManifest(
            local,
            webdav: webdavClient,
            remoteFolder: remoteFolder
        )

        report(progressCallback, SyncProgress(
            phase: .done,
            total: totalWork,
            completed: totalWork
        ))
        return result
    }

    // MARK: - Entity IO

    private func uploadEntity(_ key: String) async throws {
        guard let root = fileRoots[key] else {
            throw IncrementalSyncError.unknownEntity(key)
        }
        try await webdavClient.mkdirAll(root.remotePath)

        if isDirectory(root.localDirectory) {
            let files = try fileManager.contentsOfDirectory(
                at: root.localDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            for file in files where !isDirectory(file) {
                let data = try Data(contentsOf: file)
                let remote = "\(root.remotePath)/\(file.lastPathComponent)"
                try await webdavClient.put(remote, data: data)
            }
        } else if fileManager.fileExists(atPath: root.localDirectory.path) {
            let data = try Data(contentsOf: root.localDirectory)
            try await webdavClient.put(root.remotePath, data: data)
        }
    }

    private func downloadEntity(_ key: String) async throws {
        guard let root = fileRoots[key] else {
            throw IncrementalSyncError.unknownEntity(key)
        }

        if await webdavClient.exists(root.remotePath) {
            // Try listing first; if listing yields files, treat as directory.
            if let files = try? await webdavClient.listDirectory(root.remotePath),
               !files.filter({ !$0.isDirectory }).isEmpty {
                try fileManager.createDirectory(
                    at: root.localDirectory,
                    withIntermediateDirectories: true
                )
                for file in files where !file.isDirectory {
                    let data = try await webdavClient.get(file.path)
                    let localURL = root.localDirectory.appendingPathComponent(file.name)
                    try data.write(to: localURL, options: .atomic)
                }
            } else {
                let data = try await webdavClient.get(root.remotePath)
                let parent = root.localDirectory.deletingLastPathComponent()
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                try data.write(to: root.localDirectory, options: .atomic)
            }
        }
    }

    // MARK: - Helpers

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    private nonisolated func report(
        _ callback: (@Sendable (SyncProgress) -> Void)?,
        _ progress: SyncProgress
    ) {
        callback?(progress)
    }
}
