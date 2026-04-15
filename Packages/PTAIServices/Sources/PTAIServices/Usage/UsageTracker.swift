import Foundation

public actor UsageTracker {
    public struct Record: Hashable, Sendable, Codable, Identifiable {
        public let id: UUID
        public let modelId: String
        public let promptTokens: Int
        public let completionTokens: Int
        public let timestamp: Date
        public let conversationId: String?

        public var totalTokens: Int { promptTokens + completionTokens }

        public init(
            id: UUID = UUID(),
            modelId: String,
            promptTokens: Int,
            completionTokens: Int,
            timestamp: Date,
            conversationId: String?
        ) {
            self.id = id
            self.modelId = modelId
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.timestamp = timestamp
            self.conversationId = conversationId
        }
    }

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.directory = base
                .appendingPathComponent("papertok", isDirectory: true)
                .appendingPathComponent("usage", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func record(modelId: String, usage: TokenUsage, conversationId: String?) async {
        let now = Date()
        let record = Record(
            modelId: modelId,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            timestamp: now,
            conversationId: conversationId
        )
        let url = fileURL(for: now)
        var existing = loadRecords(at: url)
        existing.append(record)
        save(records: existing, to: url)
    }

    public func allRecords() async -> [Record] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var all: [Record] = []
        for entry in entries where entry.lastPathComponent.hasPrefix("usage-") && entry.pathExtension == "json" {
            all.append(contentsOf: loadRecords(at: entry))
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    public func records(since: Date) async -> [Record] {
        await allRecords().filter { $0.timestamp >= since }
    }

    public func records(forModel modelId: String) async -> [Record] {
        await allRecords().filter { $0.modelId == modelId }
    }

    public func totalTokens(since: Date) async -> Int {
        await records(since: since).reduce(0) { $0 + $1.totalTokens }
    }

    public func totalTokens(forModel modelId: String) async -> Int {
        await records(forModel: modelId).reduce(0) { $0 + $1.totalTokens }
    }

    public func totalTokens() async -> Int {
        await allRecords().reduce(0) { $0 + $1.totalTokens }
    }

    public func purge() async throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func fileURL(for date: Date) -> URL {
        let stamp = Self.fileDateFormatter.string(from: date)
        return directory.appendingPathComponent("usage-\(stamp).json")
    }

    private func loadRecords(at url: URL) -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([Record].self, from: data)
        } catch {
            return []
        }
    }

    private func save(records: [Record], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
