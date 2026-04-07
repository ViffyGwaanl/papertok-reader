import Foundation

// MARK: - CalendarServiceProtocol

/// Protocol injected by App Target to provide EventKit calendar access.
/// PTAIServices has no direct dependency on EventKit.
public protocol CalendarServiceProtocol: Sendable {
    func listCalendars() async throws -> [[String: Any]]
    func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String: Any]]
    func getEvent(eventId: String) async throws -> [String: Any]
    func createEvent(_ params: [String: Any]) async throws -> [String: Any]
    func updateEvent(eventId: String, params: [String: Any]) async throws -> [String: Any]
    func deleteEvent(eventId: String) async throws
}

// MARK: - Calendar Tools

public struct CalendarListCalendarsTool: AITool {
    public static let name = "calendar_list_calendars"
    public static let description = "List all device calendars with their ID, title, and color."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available. Ensure EventKit permission is granted.", isError: true)
        }
        let calendars = try await svc.listCalendars()
        return ToolResult(content: jsonString(["calendars": calendars]))
    }
}

public struct CalendarListEventsTool: AITool {
    public static let name = "calendar_list_events"
    public static let description = "List events from a calendar within a date range."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available.", isError: true)
        }
        let calendarId = arguments["calendar_id"] as? String
        let formatter = ISO8601DateFormatter()
        let startDate = (arguments["start_date"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
        let endDate = (arguments["end_date"] as? String).flatMap { formatter.date(from: $0) } ?? Date().addingTimeInterval(7 * 86400)
        let events = try await svc.listEvents(calendarId: calendarId, startDate: startDate, endDate: endDate)
        return ToolResult(content: jsonString(["events": events, "count": events.count]))
    }
}

public struct CalendarGetEventTool: AITool {
    public static let name = "calendar_get_event"
    public static let description = "Get details of a specific calendar event by ID."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available.", isError: true)
        }
        guard let eventId = arguments["event_id"] as? String else {
            return ToolResult(content: "Missing 'event_id' argument", isError: true)
        }
        let event = try await svc.getEvent(eventId: eventId)
        return ToolResult(content: jsonString(event))
    }
}

public struct CalendarCreateEventTool: AITool {
    public static let name = "calendar_create_event"
    public static let description = "Create a new calendar event with title, start/end time, location, and notes."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.dangerous
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available.", isError: true)
        }
        let event = try await svc.createEvent(arguments)
        return ToolResult(content: jsonString(["status": "created", "event": event]))
    }
}

public struct CalendarUpdateEventTool: AITool {
    public static let name = "calendar_update_event"
    public static let description = "Update an existing calendar event by ID."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.dangerous
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available.", isError: true)
        }
        guard let eventId = arguments["event_id"] as? String else {
            return ToolResult(content: "Missing 'event_id' argument", isError: true)
        }
        let event = try await svc.updateEvent(eventId: eventId, params: arguments)
        return ToolResult(content: jsonString(["status": "updated", "event": event]))
    }
}

public struct CalendarDeleteEventTool: AITool {
    public static let name = "calendar_delete_event"
    public static let description = "Delete a calendar event by ID."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.dangerous
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = context.calendarService else {
            return ToolResult(content: "Calendar service not available.", isError: true)
        }
        guard let eventId = arguments["event_id"] as? String else {
            return ToolResult(content: "Missing 'event_id' argument", isError: true)
        }
        try await svc.deleteEvent(eventId: eventId)
        return ToolResult(content: jsonString(["status": "deleted", "event_id": eventId]))
    }
}
