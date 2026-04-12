import Foundation
import Testing
import PTCore
import PTAIServices
@testable import PaperTokReader

@Suite("AppAIToolContextFactory")
struct AppAIToolContextFactoryTests {
    private final class MockCalendarService: CalendarServiceProtocol, @unchecked Sendable {
        func listCalendars() async throws -> [[String : Any]] { [] }
        func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String : Any]] { [] }
        func getEvent(eventId: String) async throws -> [String : Any] { [:] }
        func createEvent(_ params: [String : Any]) async throws -> [String : Any] { [:] }
        func updateEvent(eventId: String, params: [String : Any]) async throws -> [String : Any] { [:] }
        func deleteEvent(eventId: String) async throws {}
    }

    private final class MockRemindersService: RemindersServiceProtocol, @unchecked Sendable {
        func listLists() async throws -> [[String : Any]] { [] }
        func listReminders(listId: String?, completed: Bool?) async throws -> [[String : Any]] { [] }
        func getReminder(reminderId: String) async throws -> [String : Any] { [:] }
        func createReminder(_ params: [String : Any]) async throws -> [String : Any] { [:] }
        func updateReminder(id: String, params: [String : Any]) async throws -> [String : Any] { [:] }
        func deleteReminder(id: String) async throws {}
        func completeReminder(id: String) async throws {}
        func uncompleteReminder(id: String) async throws {}
        func createList(title: String) async throws -> [String : Any] { [:] }
        func deleteList(id: String) async throws {}
        func renameList(id: String, newTitle: String) async throws {}
    }

    @Test("tool context provisions a persistent memory directory inside the app container")
    func toolContextProvisionedMemoryDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppAIToolContextFactory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let context = try AppAIToolContextFactory.make(
            database: try AppDatabase.makeInMemory(),
            calendarService: MockCalendarService(),
            remindersService: MockRemindersService(),
            containerURL: root
        )

        let memoryDirectory = try #require(context.memoryDirectory)
        #expect(memoryDirectory == root.appendingPathComponent("memory", isDirectory: true))
        #expect(FileManager.default.fileExists(atPath: memoryDirectory.path))
        #expect(context.database != nil)
        #expect(context.calendarService != nil)
        #expect(context.remindersService != nil)
    }

    @Test("tool context keeps the shared reader session store")
    func toolContextKeepsReaderSessionStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppAIToolContextFactory-ReaderSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let readerSessionStore = ReaderSessionContextStore()
        let context = try AppAIToolContextFactory.make(
            database: try AppDatabase.makeInMemory(),
            calendarService: MockCalendarService(),
            remindersService: MockRemindersService(),
            readerSessionStore: readerSessionStore,
            containerURL: root
        )

        #expect(context.readerSessionStore === readerSessionStore)
    }
}
