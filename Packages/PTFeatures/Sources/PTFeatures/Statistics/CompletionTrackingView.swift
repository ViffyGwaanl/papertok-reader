#if canImport(SwiftUI)
import SwiftUI
import PTCore
import PTUI

/// Summarises completion stats, streaks, goal progress, and achievements.
public struct CompletionTrackingView: View {
    public struct Snapshot: Sendable, Equatable {
        public let booksThisMonth: Int
        public let booksThisYear: Int
        public let averageCompletionDays: Double
        public let currentStreak: Int
        public let longestStreak: Int
        public let dailyGoalMinutes: Int
        public let todayMinutes: Int
        public let yearlyGoalBooks: Int
        /// Day-level activity for streak heatmap (latest 12 weeks).
        public let heatmap: [DayActivity]
        public let achievements: [Achievement]

        public init(
            booksThisMonth: Int = 0,
            booksThisYear: Int = 0,
            averageCompletionDays: Double = 0,
            currentStreak: Int = 0,
            longestStreak: Int = 0,
            dailyGoalMinutes: Int = 30,
            todayMinutes: Int = 0,
            yearlyGoalBooks: Int = 12,
            heatmap: [DayActivity] = [],
            achievements: [Achievement] = []
        ) {
            self.booksThisMonth = booksThisMonth
            self.booksThisYear = booksThisYear
            self.averageCompletionDays = averageCompletionDays
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
            self.dailyGoalMinutes = dailyGoalMinutes
            self.todayMinutes = todayMinutes
            self.yearlyGoalBooks = yearlyGoalBooks
            self.heatmap = heatmap
            self.achievements = achievements
        }
    }

    public struct DayActivity: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let date: Date
        public let minutes: Int

        public init(id: UUID = UUID(), date: Date, minutes: Int) {
            self.id = id
            self.date = date
            self.minutes = minutes
        }
    }

    public struct Achievement: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let detail: String
        public let systemImage: String
        public let unlocked: Bool

        public init(id: String, title: String, detail: String, systemImage: String, unlocked: Bool) {
            self.id = id
            self.title = title
            self.detail = detail
            self.systemImage = systemImage
            self.unlocked = unlocked
        }
    }

    private let snapshot: Snapshot

    private func localized(_ key: String, _ fallback: String) -> String {
        AppLocalization.string(key, value: fallback)
    }

    private func format(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
        let formatString = AppLocalization.string(key, value: fallback)
        return String(format: formatString, locale: .autoupdatingCurrent, arguments: arguments)
    }

    public init(snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statsGrid
                goalsSection
                heatmapSection
                achievementsSection
            }
            .padding(16)
        }
        .background(Morandi.background.ignoresSafeArea())
    }

    private var statsGrid: some View {
        let items: [(String, String, Color)] = [
            (
                localized("statistics.this_month", "This Month"),
                format("statistics.books_count_format", "%d books", snapshot.booksThisMonth),
                Morandi.sage
            ),
            (
                localized("statistics.this_year", "This Year"),
                format("statistics.books_count_format", "%d books", snapshot.booksThisYear),
                Morandi.dustyRose
            ),
            (
                localized("statistics.average_completion", "Avg Completion"),
                format("statistics.average_completion_days_format", "%.1f days", snapshot.averageCompletionDays),
                Morandi.clay
            ),
            (
                localized("statistics.best_streak", "Longest Streak"),
                format("statistics.day_count_format", "%d days", snapshot.longestStreak),
                Morandi.lavender
            )
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(items, id: \.0) { item in
                statCard(title: item.0, value: item.1, accent: item.2)
            }
        }
    }

    private func statCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Morandi.secondaryText)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Morandi.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Morandi.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var goalsSection: some View {
        HStack(spacing: 16) {
            goalRing(
                progress: dailyGoalProgress,
                label: localized("statistics.daily_goal", "Daily"),
                caption: format(
                    "statistics.goal_progress_minutes_format",
                    "%d/%dm",
                    snapshot.todayMinutes,
                    snapshot.dailyGoalMinutes
                ),
                color: Morandi.sage
            )
            goalRing(
                progress: yearlyGoalProgress,
                label: localized("statistics.yearly_goal", "Yearly"),
                caption: "\(snapshot.booksThisYear)/\(snapshot.yearlyGoalBooks)",
                color: Morandi.powder
            )
            goalRing(
                progress: min(Double(snapshot.currentStreak) / 30, 1),
                label: localized("statistics.streak", "Streak"),
                caption: format("statistics.streak_short_format", "%dd", snapshot.currentStreak),
                color: Morandi.clay
            )
        }
        .padding(14)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func goalRing(progress: Double, label: String, caption: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundStyle(Morandi.primaryText)
            }
            .frame(width: 64, height: 64)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Morandi.secondaryText)
            Text(caption)
                .font(.caption2.bold())
                .foregroundStyle(Morandi.primaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("statistics.readingActivity")
                .font(.headline)
                .foregroundStyle(Morandi.primaryText)
            let columns = Array(
                repeating: GridItem(.fixed(14), spacing: 4),
                count: max(1, snapshot.heatmap.count / 7)
            )
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(snapshot.heatmap) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatColor(for: day.minutes))
                        .frame(width: 14, height: 14)
                }
            }
        }
        .padding(14)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func heatColor(for minutes: Int) -> Color {
        switch minutes {
        case 0: return Morandi.divider
        case 1..<15: return Morandi.sage.opacity(0.35)
        case 15..<45: return Morandi.sage.opacity(0.6)
        case 45..<90: return Morandi.sage.opacity(0.85)
        default: return Morandi.sage
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("statistics.achievements")
                .font(.headline)
                .foregroundStyle(Morandi.primaryText)
            ForEach(snapshot.achievements) { achievement in
                HStack(spacing: 12) {
                    Image(systemName: achievement.systemImage)
                        .font(.title3)
                        .foregroundStyle(achievement.unlocked ? Morandi.sage : Morandi.tertiaryText)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(achievement.unlocked ? Morandi.primaryText : Morandi.secondaryText)
                        Text(achievement.detail)
                            .font(.caption)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    Spacer()
                    if achievement.unlocked {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Morandi.sage)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dailyGoalProgress: Double {
        guard snapshot.dailyGoalMinutes > 0 else { return 0 }
        return Double(snapshot.todayMinutes) / Double(snapshot.dailyGoalMinutes)
    }

    private var yearlyGoalProgress: Double {
        guard snapshot.yearlyGoalBooks > 0 else { return 0 }
        return Double(snapshot.booksThisYear) / Double(snapshot.yearlyGoalBooks)
    }
}
#endif
