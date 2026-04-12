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
                Text("Reading Assistant")
            } footer: {
                Text("KAIROS helps you build a consistent reading habit with daily goals and reminders.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.tertiaryText)
            }

            if service.isEnabled {
                Section {
                    Stepper(
                        "Daily Goal: \(service.dailyGoalMinutes) min",
                        value: Binding(
                            get: { service.dailyGoalMinutes },
                            set: { service.dailyGoalMinutes = $0 }
                        ),
                        in: 5...180,
                        step: 5
                    )
                    .foregroundStyle(Morandi.primaryText)
                } header: {
                    Text("Reading Goal")
                }

                Section {
                    HStack {
                        Text("Reminder Time")
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
                    Text("Daily Reminder")
                }

                Section {
                    HStack {
                        Text("Today")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        Text("\(service.todayReadingMinutes) / \(service.dailyGoalMinutes) min")
                            .foregroundStyle(service.goalReachedToday ? Morandi.sage : Morandi.secondaryText)
                    }

                    HStack {
                        Text("Current Streak")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        Text("\(service.currentStreak) days")
                            .foregroundStyle(Morandi.accent)
                    }

                    HStack {
                        Text("Longest Streak")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        Text("\(service.longestStreak) days")
                            .foregroundStyle(Morandi.secondaryText)
                    }
                } header: {
                    Text("Progress")
                }
            }
        }
        .navigationTitle("KAIROS")
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
}

// MARK: - Helpers

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self > 0 ? self : fallback
    }
}
