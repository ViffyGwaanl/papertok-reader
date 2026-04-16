import Foundation
import Observation
import PTAIServices

/// View model for the usage dashboard. Extracts data from `UsageTracker`
/// into presentation-ready aggregates.
@MainActor @Observable
public final class UsageDashboardViewModel {
    // MARK: - Public state

    public private(set) var totalAllTime: Int = 0
    public private(set) var totalToday: Int = 0
    public private(set) var totalThisWeek: Int = 0
    public private(set) var totalThisMonth: Int = 0
    public private(set) var perModelBreakdown: [ModelBreakdown] = []
    public private(set) var dailyData: [DailyTokenData] = []
    public private(set) var isLoading: Bool = false

    // MARK: - Types

    public struct ModelBreakdown: Identifiable, Sendable {
        public let modelId: String
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        public let callCount: Int
        public var id: String { modelId }
    }

    public struct DailyTokenData: Identifiable, Sendable {
        public let date: Date
        public let promptTokens: Int
        public let completionTokens: Int
        public var id: Date { date }
    }

    // MARK: - Private

    private let tracker: UsageTracker

    public init(tracker: UsageTracker) {
        self.tracker = tracker
    }

    // MARK: - Actions

    public func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let all = await tracker.allRecords()
        let now = Date()
        let calendar = Calendar.current

        totalAllTime = all.reduce(0) { $0 + $1.totalTokens }

        let startOfToday = calendar.startOfDay(for: now)
        totalToday = all.filter { $0.timestamp >= startOfToday }.reduce(0) { $0 + $1.totalTokens }

        if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
            totalThisWeek = all.filter { $0.timestamp >= startOfWeek }.reduce(0) { $0 + $1.totalTokens }
        }

        if let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) {
            totalThisMonth = all.filter { $0.timestamp >= startOfMonth }.reduce(0) { $0 + $1.totalTokens }
        }

        // Per-model breakdown
        var byModel: [String: (prompt: Int, completion: Int, total: Int, count: Int)] = [:]
        for record in all {
            var entry = byModel[record.modelId] ?? (0, 0, 0, 0)
            entry.prompt += record.promptTokens
            entry.completion += record.completionTokens
            entry.total += record.totalTokens
            entry.count += 1
            byModel[record.modelId] = entry
        }
        perModelBreakdown = byModel.map { key, value in
            ModelBreakdown(
                modelId: key,
                promptTokens: value.prompt,
                completionTokens: value.completion,
                totalTokens: value.total,
                callCount: value.count
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        // Daily data for last 7 days
        var daily: [DailyTokenData] = []
        for dayOffset in (0..<7).reversed() {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday) else { continue }
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let dayRecords = all.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            daily.append(DailyTokenData(
                date: dayStart,
                promptTokens: dayRecords.reduce(0) { $0 + $1.promptTokens },
                completionTokens: dayRecords.reduce(0) { $0 + $1.completionTokens }
            ))
        }
        dailyData = daily
    }

    public func purgeData() async {
        try? await tracker.purge()
        await loadData()
    }
}
