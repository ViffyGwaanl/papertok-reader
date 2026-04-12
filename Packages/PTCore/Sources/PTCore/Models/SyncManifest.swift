import Foundation

/// Strategy for resolving conflicts when local and remote data diverge.
public enum ConflictStrategy: String, Codable, CaseIterable, Sendable {
    /// The most recently modified version wins automatically.
    case lastModifiedWins
    /// Local data always takes priority.
    case localWins
    /// Remote data always takes priority.
    case remoteWins
    /// Present both versions to the user for manual resolution.
    case manual
}

/// Tracks per-entity synchronisation state so incremental sync can detect
/// what has changed since the last successful sync.
public struct SyncManifest: Codable, Sendable, Equatable {
    /// When the last full sync completed successfully.
    public var lastSyncDate: Date?

    /// Per-entity version timestamps keyed by entity identifier
    /// (e.g. "books", "notes", "tags").
    public var entityVersions: [String: Date]

    /// The conflict resolution strategy to use for this manifest.
    public var conflictStrategy: ConflictStrategy

    public init(
        lastSyncDate: Date? = nil,
        entityVersions: [String: Date] = [:],
        conflictStrategy: ConflictStrategy = .lastModifiedWins
    ) {
        self.lastSyncDate = lastSyncDate
        self.entityVersions = entityVersions
        self.conflictStrategy = conflictStrategy
    }

    // MARK: - Helpers

    /// Update the version timestamp for the given entity to now.
    public mutating func markEntitySynced(_ entity: String) {
        entityVersions[entity] = Date()
    }

    /// Mark the overall sync as completed just now.
    public mutating func markSyncCompleted() {
        lastSyncDate = Date()
    }

    /// Returns `true` when the entity has never been synced.
    public func needsInitialSync(entity: String) -> Bool {
        entityVersions[entity] == nil
    }

    /// Returns the last sync date for a specific entity, if available.
    public func lastSyncDate(for entity: String) -> Date? {
        entityVersions[entity]
    }

    /// An empty manifest with default strategy (used on first launch).
    public static let empty = SyncManifest()
}
