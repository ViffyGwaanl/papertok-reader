import Foundation
import PTCore
import PTAIServices

enum AppAIToolContextFactory {
    static func make(
        database: AppDatabase,
        calendarService: any CalendarServiceProtocol,
        remindersService: any RemindersServiceProtocol,
        readerSessionStore: ReaderSessionContextStore? = nil,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ToolContext {
        let memoryDirectory = try prepareMemoryDirectory(
            containerURL: containerURL,
            fileManager: fileManager
        )

        return ToolContext(
            database: database,
            memoryDirectory: memoryDirectory,
            calendarService: calendarService,
            remindersService: remindersService,
            readerSessionStore: readerSessionStore
        )
    }

    static func prepareMemoryDirectory(
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = containerURL ?? AppConfig.appGroupContainerURL(fileManager: fileManager)
        let directory = root.appendingPathComponent("memory", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
