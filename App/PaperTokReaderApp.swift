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
        #if os(macOS)
        macOSScene
        #else
        iOSScene
        #endif
    }

    @SceneBuilder
    private var iOSScene: some Scene {
        WindowGroup {
            rootContent
                .onOpenURL { url in
                    _ = router.handle(url: url)
                }
        }
    }

    #if os(macOS)
    @SceneBuilder
    private var macOSScene: some Scene {
        MacRootScene {
            rootContent
                .onOpenURL { url in
                    _ = router.handle(url: url)
                }
        }
    }
    #endif

    @ViewBuilder
    private var rootContent: some View {
        if let environment {
            RootScene(environment: environment, showMigration: $showMigration)
                .task {
                    IntentsDonationService.refreshShortcuts()
                    let migrationService = FlutterMigrationService()
                    showMigration = await migrationService.isMigrationAvailable()
                }
        } else {
            ProgressView("Loading...")
                .task { await initializeDatabase() }
        }
    }

    private var environment: AppEnvironment? {
        guard let database else { return nil }
        return AppEnvironment(
            database: database,
            calendarService: calendarService,
            remindersService: remindersService
        )
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
