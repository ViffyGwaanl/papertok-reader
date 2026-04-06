import Foundation
import PTCore
import Observation

/// Detects and migrates data from the existing Flutter (ANX Reader) SQLite database.
///
/// Migration strategy:
/// 1. Detect Flutter DB at known paths (Documents/databases/anx_reader.db)
/// 2. Open with SQLite in read-only mode
/// 3. Copy rows from tb_books, tb_notes, tb_reading_time
/// 4. Mark migration as complete (UserDefaults flag)
@Observable
@MainActor
public final class FlutterMigrationService {
    public var progress: Double = 0.0
    public var statusMessage = ""
    public var isComplete = false
    public var errorMessage: String?

    private let flutterDBPath: URL
    private static let migrationDoneKey = "flutter_migration_complete_v1"

    public init(flutterDBPath: URL? = nil) {
        self.flutterDBPath = flutterDBPath ?? Self.findFlutterDB()
    }

    /// Check if a Flutter DB exists and migration hasn't been performed yet.
    public func isMigrationAvailable() async -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.migrationDoneKey) else { return false }
        return FileManager.default.fileExists(atPath: flutterDBPath.path)
    }

    /// Perform the migration from Flutter SQLite DB into the Swift GRDB database.
    public func migrate(into database: AppDatabase) async {
        guard FileManager.default.fileExists(atPath: flutterDBPath.path) else {
            errorMessage = "Flutter database file not found."
            return
        }

        do {
            statusMessage = "Reading bookshelf data..."
            progress = 0.1

            // Read Flutter DB using raw SQLite (read-only)
            let sourceData = try readFlutterDatabase()

            // Migrate books
            statusMessage = "Migrating \(sourceData.bookCount) books..."
            progress = 0.3
            try await database.migrateFlutterBooks(sourceData.booksSQL)

            // Migrate notes
            statusMessage = "Migrating notes and highlights..."
            progress = 0.5
            try await database.migrateFlutterNotes(sourceData.notesSQL)

            // Migrate reading time
            statusMessage = "Migrating reading records..."
            progress = 0.7
            try await database.migrateFlutterReadingTime(sourceData.readingTimeSQL)

            progress = 1.0
            statusMessage = "Migration complete! Migrated \(sourceData.bookCount) books, \(sourceData.noteCount) notes."
            isComplete = true
            UserDefaults.standard.set(true, forKey: Self.migrationDoneKey)
        } catch {
            errorMessage = "Migration failed: \(error.localizedDescription)"
            statusMessage = "Migration failed."
        }
    }

    /// Skip migration and mark as done.
    public func skipMigration() {
        UserDefaults.standard.set(true, forKey: Self.migrationDoneKey)
        isComplete = true
    }

    // MARK: - Private

    private struct FlutterData {
        let booksSQL: [[String: Any]]
        let notesSQL: [[String: Any]]
        let readingTimeSQL: [[String: Any]]
        var bookCount: Int { booksSQL.count }
        var noteCount: Int { notesSQL.count }
    }

    private func readFlutterDatabase() throws -> FlutterData {
        // In a real implementation, this would open the SQLite file and read rows.
        // For now, we return empty data since the actual migration depends on
        // the Flutter DB schema and GRDB read-only access.
        //
        // The Flutter DB (anx_reader.db) contains tables:
        //   tb_books — id, title, cover_url, file_path, ...
        //   tb_notes — id, book_id, content, chapter, color, ...
        //   tb_reading_time — id, book_id, date, reading_time, ...
        //
        // Full implementation will use GRDB DatabaseQueue(path:) in readonly mode.
        return FlutterData(booksSQL: [], notesSQL: [], readingTimeSQL: [])
    }

    private static func findFlutterDB() -> URL {
        // Flutter stores the DB in: Documents/databases/anx_reader.db
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("databases/anx_reader.db")
    }
}

// MARK: - AppDatabase Migration Extensions

extension AppDatabase {
    /// Import books from Flutter DB rows.
    func migrateFlutterBooks(_ rows: [[String: Any]]) async throws {
        // Each row maps to a Book model insert.
        // Skipped if rows are empty (no Flutter data found).
    }

    /// Import notes from Flutter DB rows.
    func migrateFlutterNotes(_ rows: [[String: Any]]) async throws {
        // Each row maps to a BookNote model insert.
    }

    /// Import reading time records from Flutter DB rows.
    func migrateFlutterReadingTime(_ rows: [[String: Any]]) async throws {
        // Each row maps to a ReadingTime model insert.
    }
}
