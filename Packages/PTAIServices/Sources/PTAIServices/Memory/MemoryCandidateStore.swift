import Foundation
import PTCore

public actor MemoryCandidateStore {
    public enum StoreError: LocalizedError {
        case candidateNotFound(String)
        case storeUnavailable

        public var errorDescription: String? {
            switch self {
            case .candidateNotFound:
                return AppLocalization.string(
                    "errors.memory.candidate_not_found",
                    value: "The selected memory item could not be found."
                )
            case .storeUnavailable:
                return AppLocalization.string(
                    "errors.memory.review_inbox_unavailable",
                    value: "Memory review items are unavailable right now."
                )
            }
        }
    }

    private struct StoreEnvelope: Codable {
        let schemaVersion: Int
        var candidates: [MemoryCandidate]
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let legacyFileURL: URL

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = directory
            .appendingPathComponent(".workflow", isDirectory: true)
            .appendingPathComponent("review_inbox_v2.json")
        self.legacyFileURL = directory
            .appendingPathComponent("review_inbox", isDirectory: true)
            .appendingPathComponent("candidates.json")
    }

    public func list(status: MemoryCandidateStatus? = nil) throws -> [MemoryCandidate] {
        let candidates = try readAll()
        let filtered = status.map { current in
            candidates.filter { $0.status == current }
        } ?? candidates
        return filtered.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id > rhs.id
        }
    }

    public func getById(_ id: String) throws -> MemoryCandidate? {
        try readAll().first { $0.id == id }
    }

    @discardableResult
    public func upsert(_ candidate: MemoryCandidate) throws -> MemoryCandidate {
        var candidates = try readAll()
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index] = candidate
        } else {
            candidates.append(candidate)
        }
        try writeAll(candidates)
        return candidate
    }

    public func markApplied(
        _ id: String,
        targetDoc: MemoryDocTarget,
        reviewedAt: Date = Date()
    ) throws -> MemoryCandidate {
        try update(id) { current in
            var updated = current
            updated.status = .applied
            updated.appliedTargetDoc = targetDoc
            updated.appliedAt = reviewedAt
            updated.reviewedAt = reviewedAt
            updated.dismissedAt = nil
            updated.decisionSource = "review_inbox"
            return updated
        }
    }

    public func updateTags(_ id: String, tags: [String]) throws -> MemoryCandidate {
        try update(id) { current in
            var updated = current
            updated.tags = tags
            return updated
        }
    }

    public func allTags() throws -> [String] {
        let candidates = try readAll()
        var seen = Set<String>()
        var ordered: [String] = []
        for candidate in candidates {
            for tag in candidate.tags where seen.insert(tag).inserted {
                ordered.append(tag)
            }
        }
        return ordered
    }

    public func dismiss(_ id: String, reviewedAt: Date = Date()) throws -> MemoryCandidate {
        try update(id) { current in
            var updated = current
            updated.status = .dismissed
            updated.reviewedAt = reviewedAt
            updated.dismissedAt = reviewedAt
            updated.appliedAt = nil
            updated.appliedTargetDoc = nil
            updated.decisionSource = "review_inbox"
            return updated
        }
    }

    private func update(
        _ id: String,
        mutate: (MemoryCandidate) -> MemoryCandidate
    ) throws -> MemoryCandidate {
        var candidates = try readAll()
        guard let index = candidates.firstIndex(where: { $0.id == id }) else {
            throw StoreError.candidateNotFound(id)
        }

        let updated = mutate(candidates[index])
        candidates[index] = updated
        try writeAll(candidates)
        return updated
    }

    private func ensureDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw StoreError.storeUnavailable
        }
    }

    private func activeStoreURL() -> URL? {
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        if fileManager.fileExists(atPath: legacyFileURL.path) {
            return legacyFileURL
        }
        return nil
    }

    private func readAll() throws -> [MemoryCandidate] {
        guard let existingURL = activeStoreURL() else {
            return []
        }

        do {
            let data = try Data(contentsOf: existingURL)
            guard data.isEmpty == false else { return [] }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let envelope = try? decoder.decode(StoreEnvelope.self, from: data) {
                return envelope.candidates
            }
            if let candidates = try? decoder.decode([MemoryCandidate].self, from: data) {
                return candidates
            }
            throw StoreError.storeUnavailable
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storeUnavailable
        }
    }

    private func writeAll(_ candidates: [MemoryCandidate]) throws {
        try ensureDirectory()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let envelope = StoreEnvelope(schemaVersion: 2, candidates: candidates)
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StoreError.storeUnavailable
        }
    }
}
