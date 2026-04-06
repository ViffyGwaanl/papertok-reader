import EventKit
import Foundation
import PTAIServices

/// Wraps EKEventStore for calendar CRUD operations.
/// Implements `CalendarServiceProtocol` defined in PTAIServices for AI tool integration.
@MainActor
public final class CalendarService: CalendarServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func listCalendars() async throws -> [[String: Any]] {
        guard await requestAccess() else { return [] }
        return store.calendars(for: .event).map { cal in
            [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                "color": hexColor(cal.cgColor),
                "isEditable": !cal.isImmutable,
            ]
        }
    }

    public func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String: Any]] {
        guard await requestAccess() else { return [] }
        let calendars: [EKCalendar]? = calendarId.flatMap { id in
            store.calendars(for: .event).filter { $0.calendarIdentifier == id }
        }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate).map { eventToMap($0) }
    }

    public func getEvent(eventId: String) async throws -> [String: Any] {
        guard await requestAccess() else { throw CalendarError.accessDenied }
        guard let event = store.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        return eventToMap(event)
    }

    public func createEvent(_ params: [String: Any]) async throws -> [String: Any] {
        guard await requestAccess() else { throw CalendarError.accessDenied }
        let event = EKEvent(eventStore: store)
        event.title = params["title"] as? String ?? "Untitled"
        event.startDate = (params["startDate"] as? Date) ?? Date()
        event.endDate = (params["endDate"] as? Date) ?? Date().addingTimeInterval(3600)
        event.notes = params["notes"] as? String
        if let calId = params["calendarId"] as? String {
            event.calendar = store.calendars(for: .event).first { $0.calendarIdentifier == calId }
        }
        event.calendar = event.calendar ?? store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return eventToMap(event)
    }

    public func updateEvent(eventId: String, params: [String: Any]) async throws -> [String: Any] {
        guard await requestAccess() else { throw CalendarError.accessDenied }
        guard let event = store.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        if let title = params["title"] as? String { event.title = title }
        if let start = params["startDate"] as? Date { event.startDate = start }
        if let end = params["endDate"] as? Date { event.endDate = end }
        if let notes = params["notes"] as? String { event.notes = notes }
        try store.save(event, span: .thisEvent)
        return eventToMap(event)
    }

    public func deleteEvent(eventId: String) async throws {
        guard await requestAccess() else { throw CalendarError.accessDenied }
        guard let event = store.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound(eventId)
        }
        try store.remove(event, span: .thisEvent)
    }

    // MARK: - Private Helpers

    private func eventToMap(_ event: EKEvent) -> [String: Any] {
        var map: [String: Any] = [
            "id": event.eventIdentifier ?? "",
            "title": event.title ?? "",
            "startDate": ISO8601DateFormatter().string(from: event.startDate),
            "endDate": ISO8601DateFormatter().string(from: event.endDate),
            "isAllDay": event.isAllDay,
        ]
        if let notes = event.notes { map["notes"] = notes }
        if let location = event.location { map["location"] = location }
        map["calendarId"] = event.calendar?.calendarIdentifier ?? ""
        return map
    }

    private func hexColor(_ cgColor: CGColor?) -> String {
        guard let components = cgColor?.components, components.count >= 3 else { return "#808080" }
        return String(format: "#%02X%02X%02X",
            Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }
}

// MARK: - CalendarError

public enum CalendarError: Error, LocalizedError {
    case accessDenied
    case eventNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Please grant permission in Settings."
        case .eventNotFound(let id):
            return "Event not found: \(id)"
        }
    }
}
