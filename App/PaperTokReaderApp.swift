import SwiftUI
import PTFeatures

@main
struct PaperTokReaderApp: App {
    @State private var database: AppDatabase?

    var body: some Scene {
        WindowGroup {
            Group {
                if let database {
                    MainTabView(database: database)
                } else {
                    ProgressView("Loading...")
                        .task { await initializeDatabase() }
                }
            }
        }
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
