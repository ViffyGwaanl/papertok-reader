import Foundation
import Observation
import PTCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// KAIROS — proactive reading reminder and goal tracking system.
///
/// Features:
/// - Daily reading goal (minutes per day)
/// - Streak tracking (consecutive days meeting goal)
/// - Scheduled reading reminders via local notifications
/// - Reading progress awareness for proactive nudges
@MainActor @Observable
public final class KAIROSService {
    // MARK: - Published State

    public private(set) var currentStreak: Int = 0
    public private(set) var longestStreak: Int = 0
    public private(set) var todayReadingMinutes: Int = 0
    public private(set) var goalReachedToday: Bool = false

    // MARK: - Settings

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            if newValue {
                scheduleReminder()
            } else {
                cancelReminder()
            }
        }
    }

    public var dailyGoalMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Keys.dailyGoal)
            return stored > 0 ? stored : Defaults.dailyGoalMinutes
        }
        set {
            defaults.set(max(1, newValue), forKey: Keys.dailyGoal)
            refreshGoalStatus()
        }
    }

    public var reminderHour: Int {
        get { defaults.integer(forKey: Keys.reminderHour).nonZeroOr(Defaults.reminderHour) }
        set {
            defaults.set(newValue, forKey: Keys.reminderHour)
            scheduleReminder()
        }
    }

    public var reminderMinute: Int {
        get { defaults.integer(forKey: Keys.reminderMinute) }
        set {
            defaults.set(newValue, forKey: Keys.reminderMinute)
            scheduleReminder()
        }
    }

    // MARK: - Private

    private let defaults: UserDefaults
    private let database: AppDatabase?

    private enum Keys {
        static let enabled = "kairos_enabled"
        static let dailyGoal = "kairos_daily_goal_minutes"
        static let reminderHour = "kairos_reminder_hour"
        static let reminderMinute = "kairos_reminder_minute"
        static let currentStreak = "kairos_current_streak"
        static let longestStreak = "kairos_longest_streak"
        static let lastStreakDate = "kairos_last_streak_date"
    }

    private enum Defaults {
        static let dailyGoalMinutes = 30
        static let reminderHour = 20 // 8 PM
    }

    // MARK: - Init

    public init(database: AppDatabase? = nil, defaults: UserDefaults = AppConfig.groupDefaults) {
        self.database = database
        self.defaults = defaults
        self.currentStreak = defaults.integer(forKey: Keys.currentStreak)
        self.longestStreak = defaults.integer(forKey: Keys.longestStreak)
    }

    /// Load today's reading data and refresh streak.
    public func refresh() async {
        guard let database else { return }

        let today = DateFormatting.dateString(from: Date())
        do {
            let todayRecords = try await database.reader.read { db in
                try ReadingTime
                    .filter(Column("date") == today)
                    .fetchAll(db)
            }
            let totalSeconds = todayRecords.reduce(0) { $0 + $1.readingTime }
            todayReadingMinutes = totalSeconds / 60
            goalReachedToday = todayReadingMinutes >= dailyGoalMinutes

            await updateStreak()
        } catch {
            // Non-critical: streak display will show cached values
        }
    }

    /// Schedule the daily reading reminder notification.
    public func scheduleReminder() {
        #if canImport(UserNotifications)
        guard isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])

        let content = UNMutableNotificationContent()
        content.title = "Time to Read"
        content.body = goalReachedToday
            ? "Great job reaching your goal! Keep the streak going."
            : "You have \(max(0, dailyGoalMinutes - todayReadingMinutes)) minutes left to reach your daily goal."
        content.sound = .default
        content.categoryIdentifier = "KAIROS_REMINDER"

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: trigger
        )

        center.add(request) { _ in }
        #endif
    }

    /// Cancel the reading reminder.
    public func cancelReminder() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        #endif
    }

    // MARK: - Streak Tracking

    private func updateStreak() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if goalReachedToday {
            let lastDateString = defaults.string(forKey: Keys.lastStreakDate) ?? ""
            let lastDate = DateFormatting.date(from: lastDateString).map { calendar.startOfDay(for: $0) }

            if let lastDate {
                let dayDifference = calendar.dateComponents([.day], from: lastDate, to: today).day ?? 0
                if dayDifference == 1 {
                    // Consecutive day
                    currentStreak += 1
                } else if dayDifference > 1 {
                    // Streak broken
                    currentStreak = 1
                }
                // dayDifference == 0 means already counted today
            } else {
                currentStreak = 1
            }

            defaults.set(DateFormatting.dateString(from: Date()), forKey: Keys.lastStreakDate)
            defaults.set(currentStreak, forKey: Keys.currentStreak)

            if currentStreak > longestStreak {
                longestStreak = currentStreak
                defaults.set(longestStreak, forKey: Keys.longestStreak)
            }
        }
    }

    private func refreshGoalStatus() {
        goalReachedToday = todayReadingMinutes >= dailyGoalMinutes
    }

    private static let notificationID = "kairos-daily-reading-reminder"
}

// MARK: - KAIROSSettingsView

import SwiftUI
import PTUI

public struct KAIROSSettingsView: View {
    @Bindable var service: KAIROSService

    public init(service: KAIROSService) {
        self.service = service
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Enable KAIROS", isOn: $service.isEnabled)
                    .tint(Morandi.accent)
                    .foregroundStyle(Morandi.primaryText)
            } header: {
                Text("settings.reading_assistant")
            } footer: {
                Text("kairos.description")
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
            }

            if service.isEnabled {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            Text("kairos.daily_goal")
                                .foregroundStyle(Morandi.primaryText)
                            Spacer()
                            Text("\(service.dailyGoalMinutes) min")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Morandi.accent)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(service.dailyGoalMinutes) },
                                set: { service.dailyGoalMinutes = Int($0) }
                            ),
                            in: 5...120,
                            step: 5
                        )
                        .tint(Morandi.accent)
                        HStack {
                            Text("5 min")
                                .font(.caption2)
                                .foregroundStyle(Morandi.tertiaryText)
                            Spacer()
                            Text("120 min")
                                .font(.caption2)
                                .foregroundStyle(Morandi.tertiaryText)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("kairos.reading_goal")
                }

                Section {
                    HStack {
                        Text("kairos.reminder_time")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { reminderDate },
                                set: { updateReminderTime($0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                } header: {
                    Text("kairos.daily_reminder")
                }

                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            Text("common.today")
                                .foregroundStyle(Morandi.primaryText)
                            Spacer()
                            Text("\(service.todayReadingMinutes) / \(service.dailyGoalMinutes) min")
                                .foregroundStyle(service.goalReachedToday ? Morandi.sage : Morandi.secondaryText)
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            let progress = min(1.0, Double(service.todayReadingMinutes) / Double(max(1, service.dailyGoalMinutes)))
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Morandi.divider)
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(service.goalReachedToday ? Morandi.sage : Morandi.accent)
                                    .frame(width: geo.size.width * progress, height: 10)
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: AppSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("kairos.current_streak")
                                .foregroundStyle(Morandi.primaryText)
                            Text("\(service.currentStreak) days")
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.accent)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("kairos.longest_streak")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        Text("\(service.longestStreak) days")
                            .foregroundStyle(Morandi.secondaryText)
                    }
                } header: {
                    Text("kairos.progress")
                }

                Section {
                    achievementRow(
                        title: "First Steps",
                        detail: "Reach your daily goal once",
                        unlocked: service.longestStreak >= 1,
                        icon: "star.fill",
                        tint: .yellow
                    )
                    achievementRow(
                        title: "Week Warrior",
                        detail: "7-day reading streak",
                        unlocked: service.longestStreak >= 7,
                        icon: "flame.fill",
                        tint: .orange
                    )
                    achievementRow(
                        title: "Unstoppable",
                        detail: "30-day reading streak",
                        unlocked: service.longestStreak >= 30,
                        icon: "crown.fill",
                        tint: Morandi.lavender
                    )
                } header: {
                    Text("kairos.achievements")
                }
            }
        }
        .navigationTitle(String(localized: "kairos.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await service.refresh()
        }
    }

    private var reminderDate: Date {
        var components = DateComponents()
        components.hour = service.reminderHour
        components.minute = service.reminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func updateReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        service.reminderHour = components.hour ?? 20
        service.reminderMinute = components.minute ?? 0
    }

    @ViewBuilder
    private func achievementRow(title: String, detail: String, unlocked: Bool, icon: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(unlocked ? tint.opacity(0.18) : Morandi.divider.opacity(0.5))
                    .frame(width: 36, height: 36)
                Image(systemName: unlocked ? icon : "lock.fill")
                    .foregroundStyle(unlocked ? tint : Morandi.tertiaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(unlocked ? Morandi.primaryText : Morandi.secondaryText)
                Text(detail)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
            }
            Spacer()
            if unlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Morandi.sage)
            }
        }
        .opacity(unlocked ? 1.0 : 0.6)
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self > 0 ? self : fallback
    }
}
