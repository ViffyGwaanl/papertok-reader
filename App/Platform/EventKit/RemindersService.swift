import EventKit
import Foundation
import PTAIServices

/// Wraps EKEventStore for reminders CRUD operations.
/// Implements `RemindersServiceProtocol` defined in PTAIServices for AI tool integration.
@MainActor
public final class RemindersService: RemindersServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    private func requestAccess() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Lists

    public func listLists() async throws -> [[String: Any]] {
        guard await requestAccess() else { return [] }
        return store.calendars(for: .reminder).map { [
            "id": $0.calendarIdentifier,
            "title": $0.title,
            "color": hexColor($0.cgColor),
        ] }
    }

    public func createList(title: String) async throws -> [String: Any] {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = title
        cal.source = store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(cal, commit: true)
        return ["id": cal.calendarIdentifier, "title": cal.title]
    }

    public func deleteList(id: String) async throws {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        if let cal = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) {
            try store.removeCalendar(cal, commit: true)
        }
    }

    public func renameList(id: String, newTitle: String) async throws {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        if let cal = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) {
            cal.title = newTitle
            try store.saveCalendar(cal, commit: true)
        }
    }

    // MARK: - Reminders

    public func listReminders(listId: String?, completed: Bool?) async throws -> [[String: Any]] {
        guard await requestAccess() else { return [] }
        let calendars: [EKCalendar]? = listId.flatMap { lid in
            store.calendars(for: .reminder).filter { $0.calendarIdentifier == lid }
        }
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let filtered = (reminders ?? []).filter { r in
                    if let comp = completed, r.isCompleted != comp { return false }
                    return true
                }
                continuation.resume(returning: filtered.map { self.reminderToMap($0) })
            }
        }
    }

    public func getReminder(reminderId: String) async throws -> [String: Any] {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                if let r = reminders?.first(where: { $0.calendarItemIdentifier == reminderId }) {
                    continuation.resume(returning: self.reminderToMap(r))
                } else {
                    continuation.resume(returning: ["error": "not_found"])
                }
            }
        }
    }

    public func createReminder(_ params: [String: Any]) async throws -> [String: Any] {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        let reminder = EKReminder(eventStore: store)
        reminder.title = params["title"] as? String ?? "Untitled"
        if let notes = params["notes"] as? String { reminder.notes = notes }
        if let due = params["dueDate"] as? Date {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        if let listId = params["listId"] as? String {
            reminder.calendar = store.calendars(for: .reminder).first {
                $0.calendarIdentifier == listId
            }
        }
        if reminder.calendar == nil {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        try store.save(reminder, commit: true)
        return reminderToMap(reminder)
    }

    public func updateReminder(id: String, params: [String: Any]) async throws -> [String: Any] {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        guard let reminder = try await fetchReminder(id: id) else {
            throw RemindersError.reminderNotFound(id)
        }
        if let title = params["title"] as? String { reminder.title = title }
        if let notes = params["notes"] as? String { reminder.notes = notes }
        if let due = params["dueDate"] as? Date {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }
        try store.save(reminder, commit: true)
        return reminderToMap(reminder)
    }

    public func deleteReminder(id: String) async throws {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        guard let reminder = try await fetchReminder(id: id) else { return }
        try store.remove(reminder, commit: true)
    }

    public func completeReminder(id: String) async throws {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        guard let reminder = try await fetchReminder(id: id) else {
            throw RemindersError.reminderNotFound(id)
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    public func uncompleteReminder(id: String) async throws {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        guard let reminder = try await fetchReminder(id: id) else {
            throw RemindersError.reminderNotFound(id)
        }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
    }

    // MARK: - Private Helpers

    private func fetchReminder(id: String) async throws -> EKReminder? {
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders?.first {
                    $0.calendarItemIdentifier == id
                })
            }
        }
    }

    private func reminderToMap(_ r: EKReminder) -> [String: Any] {
        var map: [String: Any] = [
            "id": r.calendarItemIdentifier,
            "title": r.title ?? "",
            "isCompleted": r.isCompleted,
            "listId": r.calendar.calendarIdentifier,
        ]
        if let notes = r.notes { map["notes"] = notes }
        if let due = r.dueDateComponents?.date {
            map["dueDate"] = ISO8601DateFormatter().string(from: due)
        }
        return map
    }

    private func hexColor(_ cgColor: CGColor?) -> String {
        guard let c = cgColor?.components, c.count >= 3 else { return "#808080" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

// MARK: - RemindersError

public enum RemindersError: Error, LocalizedError {
    case accessDenied
    case reminderNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access denied. Please grant permission in Settings."
        case .reminderNotFound(let id):
            return "Reminder not found: \(id)"
        }
    }
}
