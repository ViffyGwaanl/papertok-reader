import Foundation

// MARK: - CalendarServiceProtocol

/// Protocol for calendar operations, implemented by the App target using EventKit.
public protocol CalendarServiceProtocol: Sendable {
    func requestAccess() async -> Bool
    func listCalendars() async throws -> [[String: Any]]
    func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String: Any]]
    func getEvent(eventId: String) async throws -> [String: Any]
    func createEvent(_ params: [String: Any]) async throws -> [String: Any]
    func updateEvent(eventId: String, params: [String: Any]) async throws -> [String: Any]
    func deleteEvent(eventId: String) async throws
}

// MARK: - RemindersServiceProtocol

/// Protocol for reminders operations, implemented by the App target using EventKit.
public protocol RemindersServiceProtocol: Sendable {
    func listLists() async throws -> [[String: Any]]
    func listReminders(listId: String?, completed: Bool?) async throws -> [[String: Any]]
    func getReminder(reminderId: String) async throws -> [String: Any]
    func createReminder(_ params: [String: Any]) async throws -> [String: Any]
    func updateReminder(id: String, params: [String: Any]) async throws -> [String: Any]
    func deleteReminder(id: String) async throws
    func completeReminder(id: String) async throws
    func uncompleteReminder(id: String) async throws
    func createList(title: String) async throws -> [String: Any]
    func deleteList(id: String) async throws
    func renameList(id: String, newTitle: String) async throws
}
