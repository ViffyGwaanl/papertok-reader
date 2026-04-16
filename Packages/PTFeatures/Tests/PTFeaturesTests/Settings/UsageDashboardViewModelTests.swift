import Foundation
import Testing
@testable import PTFeatures
@testable import PTAIServices

@Suite("UsageDashboardViewModel")
struct UsageDashboardViewModelTests {
    @Test("total tokens aggregates all records")
    @MainActor func totalTokensAggregatesAllRecords() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-usage-\(UUID().uuidString)")
        let tracker = UsageTracker(directory: dir)

        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            conversationId: "c1"
        )
        await tracker.record(
            modelId: "claude-sonnet",
            usage: TokenUsage(promptTokens: 200, completionTokens: 100, totalTokens: 300),
            conversationId: "c2"
        )

        let vm = UsageDashboardViewModel(tracker: tracker)
        await vm.loadData()

        #expect(vm.totalAllTime == 450)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("per model breakdown groups correctly")
    @MainActor func perModelBreakdownGroupsCorrectly() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-usage-\(UUID().uuidString)")
        let tracker = UsageTracker(directory: dir)

        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            conversationId: "c1"
        )
        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 200, completionTokens: 80, totalTokens: 280),
            conversationId: "c2"
        )
        await tracker.record(
            modelId: "claude-sonnet",
            usage: TokenUsage(promptTokens: 300, completionTokens: 100, totalTokens: 400),
            conversationId: "c3"
        )

        let vm = UsageDashboardViewModel(tracker: tracker)
        await vm.loadData()

        #expect(vm.perModelBreakdown.count == 2)

        // Sorted by total desc: claude-sonnet (400) first, then gpt-4o (430)
        // Wait -- gpt-4o has 150+280=430, claude has 400. So gpt-4o is first.
        let first = vm.perModelBreakdown[0]
        #expect(first.modelId == "gpt-4o")
        #expect(first.promptTokens == 300)
        #expect(first.completionTokens == 130)
        #expect(first.totalTokens == 430)
        #expect(first.callCount == 2)

        let second = vm.perModelBreakdown[1]
        #expect(second.modelId == "claude-sonnet")
        #expect(second.totalTokens == 400)
        #expect(second.callCount == 1)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("purge calls tracker and refreshes")
    @MainActor func purgeCallsTrackerAndRefreshes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-usage-\(UUID().uuidString)")
        let tracker = UsageTracker(directory: dir)

        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            conversationId: "c1"
        )

        let vm = UsageDashboardViewModel(tracker: tracker)
        await vm.loadData()
        #expect(vm.totalAllTime == 150)

        await vm.purgeData()

        #expect(vm.totalAllTime == 0)
        #expect(vm.perModelBreakdown.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("today filter shows only today records")
    @MainActor func todayFilterShowsOnlyTodayRecords() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-usage-\(UUID().uuidString)")
        let tracker = UsageTracker(directory: dir)

        // Record today
        await tracker.record(
            modelId: "gpt-4o",
            usage: TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150),
            conversationId: "c1"
        )

        let vm = UsageDashboardViewModel(tracker: tracker)
        await vm.loadData()

        // Today's total should match since all records are from today
        #expect(vm.totalToday == 150)

        try? FileManager.default.removeItem(at: dir)
    }
}
