import SwiftUI
import PTCore
import PTFeatures
import PTAIServices

@main
struct PaperTokReaderApp: App {
    @State private var database: AppDatabase?
    @State private var router = DeepLinkRouter.shared
    @State private var showMigration = false

    // Platform services (lazy initialization — only created when needed)
    private let calendarService = CalendarService()
    private let remindersService = RemindersService()

    var body: some Scene {
        WindowGroup {
            Group {
                if let database {
                    MainTabView(database: database)
                        .sheet(isPresented: $showMigration) {
                            MigrationProgressView(database: database)
                        }
                        .onOpenURL { url in
                            _ = router.handle(url: url)
                        }
                        .task {
                            // Check for Flutter data migration on first launch
                            let migrationService = FlutterMigrationService()
                            showMigration = await migrationService.isMigrationAvailable()
                        }
                } else {
                    ProgressView("Loading...")
                        .task { await initializeDatabase() }
                }
            }
        }
        #if os(macOS)
        .commands { MacMenuCommands() }
        .defaultSize(width: 1100, height: 750)
        #endif
    }

    private func initializeDatabase() async {
        do {
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConfig.suiteName
            ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

            let dbDir = containerURL.appendingPathComponent("Database", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbPath = dbDir.appendingPathComponent("paperreader.db").path

            database = try AppDatabase.make(at: dbPath)
        } catch {
            // Fallback to in-memory for first launch debugging
            database = try? AppDatabase.makeInMemory()
        }
    }
}
