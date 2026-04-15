import Foundation
import Testing
@testable import PTAIServices

@Suite("MemoryWorkflowService")
struct MemoryWorkflowServiceTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-workflow-tests-\(UUID().uuidString)")
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

    private func makeLocalDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    @Test("review inbox supports pending applied and dismissed candidates")
    func reviewInboxFlow() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let pending = try await service.addToReviewInbox(
            text: "Remember that the user prefers jasmine tea in the afternoon.",
            targetDoc: .daily,
            sourceType: "manual",
            conversationId: "conversation-1",
            messageNodeId: "message-42",
            displayText: "Jasmine tea preference",
            bookId: 7,
            cfi: "epubcfi(/6/2[tea])",
            chapter: "Tea rituals",
            sourceKind: .manual,
            tags: ["tea", "preference"],
            rationale: "Captured manually from a durable preference."
        )

        #expect(pending.status == MemoryCandidateStatus.pending)
        #expect(pending.sourceKind == MemorySourceKind.manual)
        #expect(pending.tags == ["tea", "preference"])
        #expect(pending.conversationId == "conversation-1")
        #expect(pending.messageNodeId == "message-42")
        #expect(pending.bookId == 7)
        #expect(pending.chapter == "Tea rituals")
        #expect(pending.effectiveDisplayText == "Jasmine tea preference")
        #expect(pending.effectiveSourcePointer == "conversation-1#message-42")

        let pendingList = try await service.listCandidates(status: .pending)
        #expect(pendingList.map(\.id) == [pending.id])

        let applied = try await service.applyCandidate(
            pending.id,
            targetDoc: .longTerm
        )
        #expect(applied.status == MemoryCandidateStatus.applied)
        #expect(applied.appliedTargetDoc == MemoryDocTarget.longTerm)
        #expect(try await service.loadDocument(named: "MEMORY.md").contains("jasmine tea"))

        let dismissed = try await service.addToReviewInbox(
            text: "This note should be dismissed.",
            targetDoc: .daily,
            sourceType: "manual"
        )
        let dismissedResult = try await service.dismissCandidate(dismissed.id)
        #expect(dismissedResult.status == MemoryCandidateStatus.dismissed)

        #expect(try await service.listCandidates(status: .pending).isEmpty)
        #expect(try await service.listCandidates(status: .applied).count == 1)
        #expect(try await service.listCandidates(status: .dismissed).count == 1)
    }

    @Test("documents can be created listed saved and loaded")
    func documentLifecycle() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let now = makeLocalDate(year: 2024, month: 4, day: 14)

        let today = try await service.createTodayDocumentIfNeeded(now: now)
        #expect(today.name == "2024-04-14.md")
        #expect(today.kind == MemoryDocumentSummary.Kind.daily)

        try await service.saveDocument(
            named: "MEMORY.md",
            content: "# Long-term memory\n\nThe user is learning Swift."
        )

        let memory = try await service.loadDocument(named: "MEMORY.md")
        #expect(memory.contains("learning Swift"))

        let documents = try await service.listDocuments()
        let names = documents.map(\.name)
        #expect(names.contains("MEMORY.md"))
        #expect(names.contains("2024-04-14.md"))
    }

    @Test("search stays in sync with document writes")
    func searchAfterWrites() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let now = makeLocalDate(year: 2024, month: 4, day: 14)

        _ = try await service.saveToDaily(
            text: "The user likes jasmine tea and hand-drip coffee.",
            date: now,
            sourceType: "manual",
            sourceKind: .manual
        )
        try await service.saveDocument(
            named: "MEMORY.md",
            content: "# Long-term memory\n\nThe user studies chess openings every weekend."
        )

        let teaHits = try await service.search(query: "jasmine", limit: 10)
        #expect(teaHits.count == 1)
        #expect(teaHits.first?.path.hasSuffix("2024-04-14.md") == true)

        let chessHits = try await service.search(query: "chess", limit: 10)
        #expect(chessHits.count == 1)
        #expect(chessHits.first?.path.hasSuffix("MEMORY.md") == true)
    }

    @Test("document scaffolding and document titles are localized for Chinese locales")
    func localizedDocumentScaffolding() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let locale = Locale(identifier: "zh-Hans")
        let service = MemoryWorkflowService(directory: dir, locale: locale)
        let now = makeLocalDate(year: 2024, month: 4, day: 14, hour: 9, minute: 30)

        let today = try await service.createTodayDocumentIfNeeded(now: now)
        #expect(today.name == "2024-04-14.md")
        #expect(today.displayTitle(locale: locale) == "每日记忆 · 2024年4月14日")

        let todayContent = try await service.loadDocument(named: today.name)
        #expect(todayContent.hasPrefix("# 每日记忆 · 2024年4月14日\n\n"))

        _ = try await service.saveToLongTerm(
            text: "记住用户喜欢乌龙茶。",
            sourceType: "manual",
            sourceKind: MemorySourceKind.manual
        )
        let longTermContent = try await service.loadDocument(named: "MEMORY.md")
        #expect(longTermContent.hasPrefix("# 长期记忆\n\n"))

        let documents = try await service.listDocuments()
        let longTerm = documents.first(where: { $0.name == "MEMORY.md" })
        #expect(longTerm?.displayTitle(locale: locale) == "长期记忆")
    }
}
