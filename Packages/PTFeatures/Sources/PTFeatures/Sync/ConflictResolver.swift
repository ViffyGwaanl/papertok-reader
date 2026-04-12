import Foundation
import PTCore

/// The outcome of resolving a conflict between a local and a remote entity.
public enum ConflictResolution: Sendable, Equatable {
    /// Keep the local version; overwrite the remote.
    case useLocal
    /// Keep the remote version; overwrite the local.
    case useRemote
    /// The two versions were merged; the associated value carries the merged
    /// payload (serialized JSON).
    case merge(String)
    /// Automatic resolution not possible — UI should prompt the user.
    case askUser
}

/// A conflict between a local and a remote entity value. Used by merge logic.
public struct ConflictRecord: Sendable, Equatable {
    public let entityKey: String
    public let local: String
    public let localDate: Date
    public let remote: String
    public let remoteDate: Date

    public init(
        entityKey: String,
        local: String,
        localDate: Date,
        remote: String,
        remoteDate: Date
    ) {
        self.entityKey = entityKey
        self.local = local
        self.localDate = localDate
        self.remote = remote
        self.remoteDate = remoteDate
    }
}

/// Resolves conflicts between local and remote entities according to a
/// configurable `ConflictStrategy`.
public actor ConflictResolver {
    public let strategy: ConflictStrategy

    public init(strategy: ConflictStrategy) {
        self.strategy = strategy
    }

    /// Decide what to do with a single conflicting entity.
    public func resolve(
        entityKey: String,
        local: String,
        localDate: Date,
        remote: String,
        remoteDate: Date
    ) async -> ConflictResolution {
        switch strategy {
        case .lastModifiedWins:
            if local == remote { return .useLocal }
            if localDate == remoteDate { return .useLocal }
            return localDate > remoteDate ? .useLocal : .useRemote
        case .localWins:
            return .useLocal
        case .remoteWins:
            return .useRemote
        case .manual:
            if local == remote { return .useLocal }
            return .askUser
        }
    }

    /// Resolve every conflict in a batch. Returns a dictionary keyed by
    /// entity key whose values are the chosen resolutions.
    public func resolveAll(_ records: [ConflictRecord]) async -> [String: ConflictResolution] {
        var out: [String: ConflictResolution] = [:]
        for record in records {
            out[record.entityKey] = await resolve(
                entityKey: record.entityKey,
                local: record.local,
                localDate: record.localDate,
                remote: record.remote,
                remoteDate: record.remoteDate
            )
        }
        return out
    }

    /// Apply a previously computed resolution and return the value that
    /// should be persisted on both sides. For `.merge` it returns the merged
    /// payload; for `.askUser` it returns `nil` (caller must handle UI).
    public func applyResolution(
        _ resolution: ConflictResolution,
        to entityKey: String,
        local: String,
        remote: String
    ) async -> String? {
        switch resolution {
        case .useLocal:
            return local
        case .useRemote:
            return remote
        case .merge(let merged):
            return merged
        case .askUser:
            return nil
        }
    }

    // MARK: - Helpers

    /// Simple text merge: concatenates both versions with a marker. Callers
    /// that want richer merge semantics should build their own merger and
    /// wrap the result in `.merge(...)`.
    public nonisolated static func naiveTextMerge(local: String, remote: String) -> String {
        if local == remote { return local }
        return """
        <<<<<<< LOCAL
        \(local)
        =======
        \(remote)
        >>>>>>> REMOTE
        """
    }

    /// Convenience: decide whether `resolution` came from automatic logic or
    /// still needs user interaction.
    public nonisolated static func requiresUserInput(_ resolution: ConflictResolution) -> Bool {
        if case .askUser = resolution { return true }
        return false
    }
}
