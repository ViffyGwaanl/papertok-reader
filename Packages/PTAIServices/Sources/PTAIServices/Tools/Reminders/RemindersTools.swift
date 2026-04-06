import Foundation

// MARK: - RemindersServiceProtocol

/// Protocol injected by App Target to provide EventKit reminders access.
/// PTAIServices has no direct dependency on EventKit.
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

// MARK: - Reminders Tools

public struct RemindersListListsTool: AITool {
    public static let name = "reminders_list_lists"
    public static let description = "List all Reminders lists on the device."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.safe
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        let lists = try await svc.listLists()
        return ToolResult(content: jsonString(["lists": lists]))
    }
}

public struct RemindersListTool: AITool {
    public static let name = "reminders_list"
    public static let description = "List reminders from a specific list, optionally filtered by completion status."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.safe
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        let listId = arguments["list_id"] as? String
        let completed = arguments["completed"] as? Bool
        let reminders = try await svc.listReminders(listId: listId, completed: completed)
        return ToolResult(content: jsonString(["reminders": reminders, "count": reminders.count]))
    }
}

public struct RemindersGetTool: AITool {
    public static let name = "reminders_get"
    public static let description = "Get details of a specific reminder by ID."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.safe
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let reminderId = arguments["reminder_id"] as? String else {
            return ToolResult(content: "Missing 'reminder_id' argument", isError: true)
        }
        let reminder = try await svc.getReminder(reminderId: reminderId)
        return ToolResult(content: jsonString(reminder))
    }
}

public struct RemindersCreateTool: AITool {
    public static let name = "reminders_create"
    public static let description = "Create a new reminder with title, due date, priority, and notes."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        let reminder = try await svc.createReminder(arguments)
        return ToolResult(content: jsonString(["status": "created", "reminder": reminder]))
    }
}

public struct RemindersUpdateTool: AITool {
    public static let name = "reminders_update"
    public static let description = "Update an existing reminder by ID."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["reminder_id"] as? String else {
            return ToolResult(content: "Missing 'reminder_id' argument", isError: true)
        }
        let reminder = try await svc.updateReminder(id: id, params: arguments)
        return ToolResult(content: jsonString(["status": "updated", "reminder": reminder]))
    }
}

public struct RemindersDeleteTool: AITool {
    public static let name = "reminders_delete"
    public static let description = "Delete a reminder by ID."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["reminder_id"] as? String else {
            return ToolResult(content: "Missing 'reminder_id' argument", isError: true)
        }
        try await svc.deleteReminder(id: id)
        return ToolResult(content: jsonString(["status": "deleted", "reminder_id": id]))
    }
}

public struct RemindersCompleteTool: AITool {
    public static let name = "reminders_complete"
    public static let description = "Mark a reminder as completed."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["reminder_id"] as? String else {
            return ToolResult(content: "Missing 'reminder_id' argument", isError: true)
        }
        try await svc.completeReminder(id: id)
        return ToolResult(content: jsonString(["status": "completed", "reminder_id": id]))
    }
}

public struct RemindersUncompleteTool: AITool {
    public static let name = "reminders_uncomplete"
    public static let description = "Mark a completed reminder as not completed."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["reminder_id"] as? String else {
            return ToolResult(content: "Missing 'reminder_id' argument", isError: true)
        }
        try await svc.uncompleteReminder(id: id)
        return ToolResult(content: jsonString(["status": "uncompleted", "reminder_id": id]))
    }
}

public struct RemindersListCreateTool: AITool {
    public static let name = "reminders_list_create"
    public static let description = "Create a new Reminders list."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let title = arguments["title"] as? String else {
            return ToolResult(content: "Missing 'title' argument", isError: true)
        }
        let list = try await svc.createList(title: title)
        return ToolResult(content: jsonString(["status": "created", "list": list]))
    }
}

public struct RemindersListDeleteTool: AITool {
    public static let name = "reminders_list_delete"
    public static let description = "Delete a Reminders list by ID."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["list_id"] as? String else {
            return ToolResult(content: "Missing 'list_id' argument", isError: true)
        }
        try await svc.deleteList(id: id)
        return ToolResult(content: jsonString(["status": "deleted", "list_id": id]))
    }
}

public struct RemindersListRenameTool: AITool {
    public static let name = "reminders_list_rename"
    public static let description = "Rename a Reminders list."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.dangerous
    public var remindersService: (any RemindersServiceProtocol)?

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        guard let id = arguments["list_id"] as? String,
              let newTitle = arguments["new_title"] as? String else {
            return ToolResult(content: "Missing 'list_id' or 'new_title' argument", isError: true)
        }
        try await svc.renameList(id: id, newTitle: newTitle)
        return ToolResult(content: jsonString(["status": "renamed", "list_id": id, "new_title": newTitle]))
    }
}
