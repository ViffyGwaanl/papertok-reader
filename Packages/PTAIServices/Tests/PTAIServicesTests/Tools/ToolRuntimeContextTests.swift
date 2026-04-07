import Foundation
import Testing
@testable import PTAIServices

@Suite("Tool runtime context")
struct ToolRuntimeContextTests {
    final class MockCalendarService: CalendarServiceProtocol, @unchecked Sendable {
        func listCalendars() async throws -> [[String : Any]] {
            [["id": "cal-1", "title": "Work"]]
        }

        func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String : Any]] {
            []
        }

        func getEvent(eventId: String) async throws -> [String : Any] {
            [:]
        }

        func createEvent(_ params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func updateEvent(eventId: String, params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func deleteEvent(eventId: String) async throws {}
    }

    final class MockRemindersService: RemindersServiceProtocol, @unchecked Sendable {
        func listLists() async throws -> [[String : Any]] {
            [["id": "list-1", "title": "Inbox"]]
        }

        func listReminders(listId: String?, completed: Bool?) async throws -> [[String : Any]] {
            []
        }

        func getReminder(reminderId: String) async throws -> [String : Any] {
            [:]
        }

        func createReminder(_ params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func updateReminder(id: String, params: [String : Any]) async throws -> [String : Any] {
            [:]
        }

        func deleteReminder(id: String) async throws {}

        func completeReminder(id: String) async throws {}

        func uncompleteReminder(id: String) async throws {}

        func createList(title: String) async throws -> [String : Any] {
            [:]
        }

        func deleteList(id: String) async throws {}

        func renameList(id: String, newTitle: String) async throws {}
    }

    struct MockSubAgentService: SubAgentServiceProtocol {
        func spawn(task: String, type: String, requestedSteps: Int?) async throws -> SubAgentSpawnResult {
            SubAgentSpawnResult(
                status: "completed",
                summary: "summarized \(task)",
                agentType: type,
                requestedSteps: requestedSteps
            )
        }
    }

    struct MockShortcutsService: ShortcutsServiceProtocol {
        func runShortcut(named name: String, input: String?) async throws -> ShortcutsRunResult {
            ShortcutsRunResult(
                status: "opened",
                shortcutName: name,
                detail: input ?? "no-input"
            )
        }
    }

    private func jsonObject(_ string: String) -> [String: Any] {
        let data = Data(string.utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test("calendar tools read calendar service from ToolContext")
    func calendarToolUsesContextService() async throws {
        let result = try await CalendarListCalendarsTool().execute(
            arguments: [:],
            context: ToolContext(calendarService: MockCalendarService())
        )

        let payload = jsonObject(result.content)
        let calendars = payload["calendars"] as? [[String: Any]]
        #expect(calendars?.count == 1)
        #expect(calendars?.first?["id"] as? String == "cal-1")
    }

    @Test("reminders tools read reminders service from ToolContext")
    func remindersToolUsesContextService() async throws {
        let result = try await RemindersListListsTool().execute(
            arguments: [:],
            context: ToolContext(remindersService: MockRemindersService())
        )

        let payload = jsonObject(result.content)
        let lists = payload["lists"] as? [[String: Any]]
        #expect(lists?.count == 1)
        #expect(lists?.first?["id"] as? String == "list-1")
    }

    @Test("spawn_sub_agent returns typed unsupported result without runtime")
    func spawnSubAgentUnsupportedWithoutRuntime() async throws {
        let result = try await SpawnSubAgentTool().execute(
            arguments: ["task": "summarize", "type": "research"],
            context: ToolContext()
        )

        let payload = jsonObject(result.content)
        #expect(result.isError)
        #expect(payload["status"] as? String == "unsupported")
        #expect(payload["requires"] as? String == "subAgentService")
    }

    @Test("spawn_sub_agent uses ToolContext runtime when available")
    func spawnSubAgentUsesRuntime() async throws {
        let result = try await SpawnSubAgentTool().execute(
            arguments: ["task": "summarize chapter 1", "type": "research", "steps": 3],
            context: ToolContext(subAgentService: MockSubAgentService())
        )

        let payload = jsonObject(result.content)
        #expect(result.isError == false)
        #expect(payload["status"] as? String == "completed")
        #expect(payload["agent_type"] as? String == "research")
    }

    @Test("shortcuts_run returns typed unsupported result without runtime")
    func shortcutsRunUnsupportedWithoutRuntime() async throws {
        let result = try await ShortcutsRunTool().execute(
            arguments: ["shortcut_name": "Morning Routine"],
            context: ToolContext()
        )

        let payload = jsonObject(result.content)
        #expect(result.isError)
        #expect(payload["status"] as? String == "unsupported")
        #expect(payload["requires"] as? String == "shortcutsService")
    }

    @Test("shortcuts_run uses ToolContext runtime when available")
    func shortcutsRunUsesRuntime() async throws {
        let result = try await ShortcutsRunTool().execute(
            arguments: ["shortcut_name": "Morning Routine", "input": "today"],
            context: ToolContext(shortcutsService: MockShortcutsService())
        )

        let payload = jsonObject(result.content)
        #expect(result.isError == false)
        #expect(payload["status"] as? String == "opened")
        #expect(payload["shortcut_name"] as? String == "Morning Routine")
    }
}
