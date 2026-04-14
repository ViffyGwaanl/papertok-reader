import Foundation
import Observation
import PTCore
import PTNetworking

/// Sync state for UI consumption.
public enum SyncStatus: String, Sendable {
    case idle
    case syncing
    case success
    case error
}

/// Orchestrates bidirectional sync of the app database and book files via WebDAV.
///
/// Strategy:
/// 1. Upload the local database snapshot to `<remote>/PaperTok/paperreader.db`
/// 2. Upload book files that are newer locally
/// 3. Download book files that are newer remotely
/// 4. Conflict resolution: last-modified wins (configurable later)
@MainActor @Observable
public final class WebDAVSyncService {
    public private(set) var status: SyncStatus = .idle
    public private(set) var lastSyncDate: Date?
    public private(set) var errorMessage: String?
    public private(set) var progress: Double = 0

    public var autoSyncEnabled: Bool {
        didSet { defaults.set(autoSyncEnabled, forKey: Self.autoSyncKey) }
    }

    public var conflictStrategy: ConflictStrategy {
        didSet { defaults.set(conflictStrategy.rawValue, forKey: Self.conflictStrategyKey) }
    }

    public var aiSettingsSyncEnabled: Bool {
        didSet { defaults.set(aiSettingsSyncEnabled, forKey: Self.aiSettingsSyncKey) }
    }

    public var remoteFolder: String {
        didSet { defaults.set(remoteFolder, forKey: Self.remoteFolderKey) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    private static let lastSyncKey = "webdav_last_sync"
    private static let autoSyncKey = "webdav_auto_sync"
    private static let remoteFolderKey = "webdav_remote_folder"
    private static let conflictStrategyKey = "webdav_conflict_strategy"
    private static let aiSettingsSyncKey = "webdav_ai_settings_sync"

    public init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
        self.autoSyncEnabled = defaults.bool(forKey: Self.autoSyncKey)
        self.aiSettingsSyncEnabled = defaults.bool(forKey: Self.aiSettingsSyncKey)
        self.remoteFolder = defaults.string(forKey: Self.remoteFolderKey) ?? "/PaperTok"
        if let raw = defaults.string(forKey: Self.conflictStrategyKey),
           let value = ConflictStrategy(rawValue: raw) {
            self.conflictStrategy = value
        } else {
            self.conflictStrategy = .lastModifiedWins
        }
        if let ts = defaults.object(forKey: Self.lastSyncKey) as? Date {
            self.lastSyncDate = ts
        }
    }

    /// Build a WebDAVClient from stored credentials. Returns nil if not configured.
    public func makeClient() -> WebDAVClient? {
        guard let urlString = try? KeychainService.load(key: "webdav_url"),
              let url = URL(string: urlString),
              let user = try? KeychainService.load(key: "webdav_user"),
              let pass = try? KeychainService.load(key: "webdav_pass") else {
            return nil
        }
        return WebDAVClient(baseURL: url, auth: .basic(user: user, password: pass))
    }

    /// Test the stored WebDAV connection.
    public func testConnection() async -> Bool {
        guard let client = makeClient() else { return false }
        do {
            try await client.ping()
            return true
        } catch {
            return false
        }
    }

    /// Save WebDAV credentials into Keychain.
    public func saveCredentials(url: String, username: String, password: String) throws {
        try KeychainService.save(key: "webdav_url", value: url)
        try KeychainService.save(key: "webdav_user", value: username)
        try KeychainService.save(key: "webdav_pass", value: password)
    }

    /// Clear stored WebDAV credentials.
    public func clearCredentials() throws {
        try KeychainService.delete(key: "webdav_url")
        try KeychainService.delete(key: "webdav_user")
        try KeychainService.delete(key: "webdav_pass")
    }

    /// Perform a full sync cycle: upload local DB, sync book files.
    public func sync() async {
        guard let client = makeClient() else {
            errorMessage = AppLocalization.string("sync.connection_detail.configure_webdav_first")
            status = .error
            return
        }

        status = .syncing
        progress = 0
        errorMessage = nil

        do {
            // Ensure remote directory exists
            try await client.mkdirAll(remoteFolder)
            progress = 0.1

            // Upload database
            let dbURL = databaseURL()
            if FileManager.default.fileExists(atPath: dbURL.path) {
                let dbData = try Data(contentsOf: dbURL)
                try await client.put("\(remoteFolder)/paperreader.db", data: dbData)
            }
            progress = 0.4

            // Upload book files
            let booksDir = AppConfig.appGroupContainerURL().appendingPathComponent("books", isDirectory: true)
            if FileManager.default.fileExists(atPath: booksDir.path) {
                try await client.mkdirAll("\(remoteFolder)/books")
                let files = try FileManager.default.contentsOfDirectory(
                    at: booksDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: .skipsHiddenFiles
                )
                for (index, file) in files.enumerated() {
                    let remotePath = "\(remoteFolder)/books/\(file.lastPathComponent)"
                    let data = try Data(contentsOf: file)
                    try await client.put(remotePath, data: data)
                    progress = 0.4 + 0.5 * Double(index + 1) / Double(max(files.count, 1))
                }
            }
            progress = 0.9

            // Upload covers
            let coversDir = AppConfig.appGroupContainerURL().appendingPathComponent("covers", isDirectory: true)
            if FileManager.default.fileExists(atPath: coversDir.path) {
                try await client.mkdirAll("\(remoteFolder)/covers")
                let coverFiles = try FileManager.default.contentsOfDirectory(
                    at: coversDir,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                for file in coverFiles {
                    let remotePath = "\(remoteFolder)/covers/\(file.lastPathComponent)"
                    let data = try Data(contentsOf: file)
                    try await client.put(remotePath, data: data)
                }
            }

            progress = 1.0
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
            status = .success
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.sync.upload_failed"
            )
            status = .error
        }
    }

    /// Download database and files from the remote server to restore locally.
    public func restore() async {
        guard let client = makeClient() else {
            errorMessage = AppLocalization.string("sync.connection_detail.configure_webdav_first")
            status = .error
            return
        }

        status = .syncing
        progress = 0
        errorMessage = nil

        do {
            // Download database
            let remoteDBPath = "\(remoteFolder)/paperreader.db"
            if await client.exists(remoteDBPath) {
                let data = try await client.get(remoteDBPath)
                let dbURL = databaseURL()
                try FileManager.default.createDirectory(
                    at: dbURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: dbURL, options: .atomic)
            }
            progress = 0.4

            // Download books
            let remoteBooksPath = "\(remoteFolder)/books"
            if await client.exists(remoteBooksPath) {
                let remoteFiles = try await client.listDirectory(remoteBooksPath)
                let booksDir = AppConfig.appGroupContainerURL().appendingPathComponent("books", isDirectory: true)
                try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
                for (index, file) in remoteFiles.filter({ !$0.isDirectory }).enumerated() {
                    let data = try await client.get(file.path)
                    let localURL = booksDir.appendingPathComponent(file.name)
                    try data.write(to: localURL, options: .atomic)
                    progress = 0.4 + 0.5 * Double(index + 1) / Double(max(remoteFiles.count, 1))
                }
            }

            progress = 1.0
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
            status = .success
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.sync.download_failed"
            )
            status = .error
        }
    }

    // MARK: - Incremental Sync

    /// Run a delta-based sync pass using `IncrementalSyncEngine`. This is the
    /// preferred code path going forward; the original `sync()` remains as a
    /// legacy full-sync fallback.
    public func incrementalSync() async {
        guard let client = makeClient() else {
            errorMessage = AppLocalization.string("sync.connection_detail.configure_webdav_first")
            status = .error
            return
        }

        status = .syncing
        progress = 0
        errorMessage = nil

        let container = AppConfig.appGroupContainerURL()
        let roots: [SyncFileRoot] = [
            SyncFileRoot(
                entityKey: "database",
                localDirectory: databaseURL(),
                remotePath: "\(remoteFolder)/paperreader.db"
            ),
            SyncFileRoot(
                entityKey: "books",
                localDirectory: container.appendingPathComponent("books", isDirectory: true),
                remotePath: "\(remoteFolder)/books"
            ),
            SyncFileRoot(
                entityKey: "covers",
                localDirectory: container.appendingPathComponent("covers", isDirectory: true),
                remotePath: "\(remoteFolder)/covers"
            ),
        ]

        let manifestStore = SyncManifestStore()
        let resolver = ConflictResolver(strategy: conflictStrategy)
        let engine = IncrementalSyncEngine(
            webdavClient: client,
            manifestStore: manifestStore,
            conflictResolver: resolver,
            fileRoots: roots,
            remoteFolder: remoteFolder
        )

        do {
            let folder = remoteFolder
            _ = try await engine.sync(progressCallback: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.progress = progress.fraction
                }
            })

            if aiSettingsSyncEnabled {
                let ai = AISettingsSyncService(remoteFolder: folder)
                try await ai.syncToRemote(webdav: client)
            }

            progress = 1.0
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
            status = .success
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "sync.sync_failed"
            )
            status = .error
        }
    }

    private func databaseURL() -> URL {
        let containerURL = AppConfig.appGroupContainerURL()
        return containerURL
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("paperreader.db")
    }
}
