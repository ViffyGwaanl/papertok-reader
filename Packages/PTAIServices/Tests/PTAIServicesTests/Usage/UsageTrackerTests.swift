import Foundation
import Testing
@testable import PTAIServices

@Suite("UsageTracker")
struct UsageTrackerTests {
    private static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageTrackerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("recordAppendsToTodayFile")
    func recordAppendsToTodayFile() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)

        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30),
            conversationId: "conv-1"
        )
        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 5, completionTokens: 7, totalTokens: 12),
            conversationId: "conv-1"
        )

        let all = await tracker.allRecords()
        #expect(all.count == 2)
        #expect(all.map(\.totalTokens).reduce(0, +) == 42)

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent.hasPrefix("usage-") ?? false)
    }

    @Test("allRecordsReturnsAcrossDays")
    func allRecordsReturnsAcrossDays() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Hand-seed two day files.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let day1 = UsageTracker.Record(
            modelId: "gpt-4o",
            promptTokens: 1, completionTokens: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            conversationId: nil
        )
        let day2 = UsageTracker.Record(
            modelId: "claude",
            promptTokens: 3, completionTokens: 4,
            timestamp: Date(timeIntervalSince1970: 1_700_100_000),
            conversationId: nil
        )
        try encoder.encode([day1]).write(to: dir.appendingPathComponent("usage-2023-11-14.json"))
        try encoder.encode([day2]).write(to: dir.appendingPathComponent("usage-2023-11-15.json"))

        let tracker = UsageTracker(directory: dir)
        let all = await tracker.allRecords()
        #expect(all.count == 2)
    }

    @Test("recordsSinceDateFilters")
    func recordsSinceDateFilters() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        await tracker.record(
            modelId: "m",
            usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2),
            conversationId: nil
        )

        let future = Date().addingTimeInterval(3600)
        let past = Date().addingTimeInterval(-3600)
        let sinceFuture = await tracker.records(since: future)
        let sincePast = await tracker.records(since: past)
        #expect(sinceFuture.isEmpty)
        #expect(sincePast.count == 1)
    }

    @Test("recordsForModelFilters")
    func recordsForModelFilters() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        await tracker.record(modelId: "a", usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2), conversationId: nil)
        await tracker.record(modelId: "b", usage: TokenUsage(promptTokens: 3, completionTokens: 3, totalTokens: 6), conversationId: nil)

        let onlyA = await tracker.records(forModel: "a")
        #expect(onlyA.count == 1)
        #expect(onlyA.first?.modelId == "a")
    }

    @Test("totalTokensAggregatesCorrectly")
    func totalTokensAggregatesCorrectly() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        await tracker.record(modelId: "x", usage: TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30), conversationId: nil)
        await tracker.record(modelId: "x", usage: TokenUsage(promptTokens: 5, completionTokens: 5, totalTokens: 10), conversationId: nil)
        await tracker.record(modelId: "y", usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2), conversationId: nil)

        let totalAll = await tracker.totalTokens()
        let totalX = await tracker.totalTokens(forModel: "x")
        #expect(totalAll == 42)
        #expect(totalX == 40)
    }

    @Test("purgeRemovesAllRecords")
    func purgeRemovesAllRecords() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = UsageTracker(directory: dir)
        await tracker.record(modelId: "m", usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2), conversationId: nil)
        try await tracker.purge()
        let after = await tracker.allRecords()
        #expect(after.isEmpty)
    }

    @Test("corruptedFileIsSkipped")
    func corruptedFileIsSkipped() async throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not json".data(using: .utf8)!
            .write(to: dir.appendingPathComponent("usage-2023-01-01.json"))

        let tracker = UsageTracker(directory: dir)
        await tracker.record(
            modelId: "m",
            usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2),
            conversationId: nil
        )
        let all = await tracker.allRecords()
        #expect(all.count == 1)
    }
}
