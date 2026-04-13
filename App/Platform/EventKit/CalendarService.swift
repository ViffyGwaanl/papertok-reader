import EventKit
import Foundation
import PTCore
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
        event.title = stringValue(["title"], from: params) ?? AppLocalization.string("common.untitled", value: "Untitled")
        event.startDate = dateValue(["start_date", "startDate"], from: params) ?? Date()
        event.endDate = dateValue(["end_date", "endDate"], from: params) ?? Date().addingTimeInterval(3600)
        event.notes = stringValue(["notes"], from: params)
        event.location = stringValue(["location"], from: params)
        if let calId = stringValue(["calendar_id", "calendarId"], from: params) {
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
        if let title = stringValue(["title"], from: params) { event.title = title }
        if let start = dateValue(["start_date", "startDate"], from: params) { event.startDate = start }
        if let end = dateValue(["end_date", "endDate"], from: params) { event.endDate = end }
        if let notes = stringValue(["notes"], from: params) { event.notes = notes }
        if let location = stringValue(["location"], from: params) { event.location = location }
        if let calId = stringValue(["calendar_id", "calendarId"], from: params) {
            event.calendar = store.calendars(for: .event).first { $0.calendarIdentifier == calId } ?? event.calendar
        }
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

    private func stringValue(_ keys: [String], from params: [String: Any]) -> String? {
        for key in keys {
            if let value = params[key] as? String {
                return value
            }
        }
        return nil
    }

    private func dateValue(_ keys: [String], from params: [String: Any]) -> Date? {
        for key in keys {
            if let value = params[key] as? Date {
                return value
            }
            if let value = params[key] as? String,
               let date = Self.iso8601FormatterWithFractionalSeconds.date(from: value) ?? Self.iso8601Formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static let iso8601FormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

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
            return AppLocalization.string(
                "errors.calendar.access_denied",
                value: "Calendar access denied. Please grant permission in Settings."
            )
        case .eventNotFound(let id):
            return AppLocalization.format(
                "errors.calendar.event_not_found_format",
                "Event not found: %@",
                id
            )
        }
    }
}
