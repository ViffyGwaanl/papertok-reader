import Foundation
import Testing
@testable import PTAIServices

@Suite("MemoryContextBuilder")
struct MemoryContextBuilderTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-context-builder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeLocalDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }

    @Test("buildContext localizes section headers for Chinese locales")
    func localizedContextSections() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        # 长期记忆

        用户喜欢乌龙茶。
        """.write(
            to: dir.appendingPathComponent("MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )

        try """
        # 每日记忆 · 2024年4月14日

        今天继续完善阅读器。
        """.write(
            to: dir.appendingPathComponent("2024-04-14.md"),
            atomically: true,
            encoding: .utf8
        )

        let builder = MemoryContextBuilder(locale: Locale(identifier: "zh-Hans"))
        let context = try await builder.buildContext(
            memoryDirectory: dir,
            lookbackDays: 30,
            maxChars: 2000,
            now: makeLocalDate(year: 2024, month: 4, day: 14)
        )

        #expect(context.contains("## 记忆上下文"))
        #expect(context.contains("### 长期记忆"))
        #expect(context.contains("### 每日记忆 · 2024年4月14日"))
        #expect(context.contains("Persistent memory context") == false)
    }

    @Test("buildContext uses a localized truncation marker for Chinese locales")
    func localizedTruncationMarker() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        这是第一段长期记忆。
        这是第二段长期记忆。
        这是第三段长期记忆。
        """.write(
            to: dir.appendingPathComponent("MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )

        let builder = MemoryContextBuilder(locale: Locale(identifier: "zh-Hans"))
        let context = try await builder.buildContext(
            memoryDirectory: dir,
            lookbackDays: 30,
            maxChars: 40,
            now: makeLocalDate(year: 2024, month: 4, day: 14)
        )

        #expect(context.contains("…（已截断）"))
        #expect(context.contains("…(truncated)") == false)
    }

    @Test("buildContext uses a localized truncation marker for traditional Chinese")
    func localizedTraditionalChineseTruncationMarker() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        這是第一段長期記憶。
        這是第二段長期記憶。
        這是第三段長期記憶。
        """.write(
            to: dir.appendingPathComponent("MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )

        let builder = MemoryContextBuilder(locale: Locale(identifier: "zh-Hant"))
        let context = try await builder.buildContext(
            memoryDirectory: dir,
            lookbackDays: 30,
            maxChars: 40,
            now: makeLocalDate(year: 2024, month: 4, day: 14)
        )

        #expect(context.contains("…（已截斷）"))
        #expect(context.contains("…(truncated)") == false)
    }
}
