import Foundation
import GRDB
import PTCore
import Observation

/// Detects and migrates data from the existing Flutter (ANX Reader) SQLite database.
///
/// Migration strategy:
/// 1. Detect Flutter DB at known paths (Documents/databases/anx_reader.db)
/// 2. Open with SQLite in read-only mode
/// 3. Copy rows from tb_books, tb_notes, tb_reading_time
/// 4. Persist per-step progress so migration is restart-safe and only marked complete for the supported scope.
@Observable
@MainActor
public final class FlutterMigrationService {
    struct LegacyDatabaseMetadata: Equatable {
        let userVersion: Int
        let tables: Set<String>
    }

    enum LegacyDatabasePreflightError: Error, Equatable {
        case unsupportedSchema(Int)
        case missingRequiredTables(Set<String>)
    }

    nonisolated static let expectedLegacySchemaVersion = 7
    nonisolated static let requiredLegacyTables: Set<String> = [
        "tb_books",
        "tb_notes",
        "tb_reading_time",
        "tb_themes",
        "tb_styles",
        "tb_groups",
        "tb_tags",
        "tb_book_tags",
    ]

    public var progress: Double = 0.0
    public var statusMessage = ""
    public var isComplete = false
    public var errorMessage: String?

    private let flutterDBPath: URL
    private let legacyDefaults: UserDefaults
    private static let legacyMigrationDoneKey = "flutter_migration_complete_v1"
    private static let migrationStateKey = "flutter_migration_state_v2"

    public init(flutterDBPath: URL? = nil, legacyDefaults: UserDefaults = .standard) {
        self.flutterDBPath = flutterDBPath ?? Self.findFlutterDB()
        self.legacyDefaults = legacyDefaults
        // If a previous build set a one-way completion flag, don't re-run automatically (could duplicate).
        // We explicitly model this as "legacy done (unknown scope)" instead of pretending it's a full migration.
        if Self.loadState() == nil, UserDefaults.standard.bool(forKey: Self.legacyMigrationDoneKey) {
            isComplete = true
        } else if let state = Self.loadState(), state.isFinished {
            isComplete = true
        }
    }

    /// Check if a Flutter DB exists and migration hasn't been performed yet.
    public func isMigrationAvailable() async -> Bool {
        guard FileManager.default.fileExists(atPath: flutterDBPath.path) else { return false }

        // Back-compat: older builds only stored a boolean flag. Treat as "already handled" to avoid duplicates.
        if UserDefaults.standard.bool(forKey: Self.legacyMigrationDoneKey), Self.loadState() == nil {
            return false
        }

        guard let state = Self.loadState() else { return true }
        // If the source DB changed since last run, treat migration as available again.
        guard state.matchesCurrentSource(at: flutterDBPath) else { return true }
        return !state.isFinished
    }

    /// Perform the migration from Flutter SQLite DB into the Swift GRDB database.
    public func migrate(into database: AppDatabase) async {
        guard FileManager.default.fileExists(atPath: flutterDBPath.path) else {
            errorMessage = localized("migration.error.db_not_found")
            return
        }

        do {
            statusMessage = localized("migration.status.preparing")
            progress = 0.02
            _ = try Self.validateLegacyDatabase(at: flutterDBPath)

            var state = Self.loadState()
                .flatMap { $0.matchesCurrentSource(at: flutterDBPath) ? $0 : nil }
                ?? PersistedMigrationState.new(for: flutterDBPath)

            // If a legacy flag is set but we don't have detailed state, don't silently "succeed".
            // This keeps behavior safe (no re-import) and messaging honest.
            if UserDefaults.standard.bool(forKey: Self.legacyMigrationDoneKey), Self.loadState() == nil {
                statusMessage = localized("migration.status.legacy_done")
                progress = 1.0
                isComplete = true
                return
            }

            errorMessage = nil
            statusMessage = localized("migration.status.reading_bookshelf")
            progress = 0.05 + (Double(state.completedSteps.count) / Double(PersistedMigrationState.Step.allCases.count)) * 0.75
            state.status = .inProgress
            state.lastError = nil
            Self.saveState(state)

            // Read Flutter DB using raw SQLite (read-only)
            let sourceData = try readFlutterDatabase()
            let legacyRoot = FlutterMigrationPlanner.legacyRoot(from: flutterDBPath)
            let destinationRoot = FlutterMigrationPlanner.destinationRoot()
            state.lastObservedCounts = .init(
                books: sourceData.bookCount,
                notes: sourceData.noteCount,
                readingTime: sourceData.readingTimeCount
            )
            Self.saveState(state)

            // Migrate supported tables. We only mark completion once all supported steps are finished.
            if !state.completedSteps.contains(.books) {
                statusMessage = localizedFormat("migration.status.migrating_books_count", Int64(sourceData.bookCount))
                progress = 0.25
                Self.saveState(state.markingStarted(.books))
                let migratedBooks = try sourceData.books.map {
                    try FlutterMigrationPlanner.remapBook(
                        $0,
                        legacyRoot: legacyRoot,
                        destinationRoot: destinationRoot
                    )
                }
                try await database.migrateFlutterBooks(migratedBooks)
                state = state.markingCompleted(.books)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.notes) {
                statusMessage = localized("migration.status.migrating_notes")
                progress = 0.55
                Self.saveState(state.markingStarted(.notes))
                try await database.migrateFlutterNotes(sourceData.notes)
                state = state.markingCompleted(.notes)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.readingTime) {
                statusMessage = localized("migration.status.migrating_reading_records")
                progress = 0.8
                Self.saveState(state.markingStarted(.readingTime))
                try await database.migrateFlutterReadingTime(sourceData.readingTime)
                state = state.markingCompleted(.readingTime)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.themes) {
                statusMessage = localized("migration.status.migrating_themes")
                progress = 0.88
                Self.saveState(state.markingStarted(.themes))
                try await database.migrateFlutterThemes(sourceData.themes)
                state = state.markingCompleted(.themes)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.styles) {
                statusMessage = localized("migration.status.migrating_styles")
                progress = 0.9
                Self.saveState(state.markingStarted(.styles))
                try await database.migrateFlutterStyles(sourceData.styles)
                state = state.markingCompleted(.styles)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.groups) {
                statusMessage = localized("migration.status.migrating_groups")
                progress = 0.92
                Self.saveState(state.markingStarted(.groups))
                try await database.migrateFlutterGroups(sourceData.groups)
                state = state.markingCompleted(.groups)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.tags) {
                statusMessage = localized("migration.status.migrating_tags")
                progress = 0.94
                Self.saveState(state.markingStarted(.tags))
                try await database.migrateFlutterTags(sourceData.tags)
                state = state.markingCompleted(.tags)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.bookTags) {
                statusMessage = localized("migration.status.migrating_book_tags")
                progress = 0.95
                Self.saveState(state.markingStarted(.bookTags))
                try await database.migrateFlutterBookTags(sourceData.bookTags)
                state = state.markingCompleted(.bookTags)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.memory) {
                statusMessage = localized("migration.status.migrating_memory")
                progress = 0.97
                Self.saveState(state.markingStarted(.memory))
                _ = try FlutterMigrationPlanner.copyMemoryIfPresent(
                    legacyRoot: legacyRoot,
                    destinationRoot: destinationRoot
                )
                state = state.markingCompleted(.memory)
                Self.saveState(state)
            }

            if !state.completedSteps.contains(.settings) {
                statusMessage = localized("migration.status.migrating_settings")
                progress = 0.99
                Self.saveState(state.markingStarted(.settings))
                _ = FlutterMigrationPlanner.importLegacySettingsIfNeeded(
                    from: legacyDefaults,
                    to: AppConfig.groupDefaults
                )
                state = state.markingCompleted(.settings)
                Self.saveState(state)
            }

            progress = 1.0
            statusMessage = localizedFormat(
                "migration.status.complete_summary",
                Int64(sourceData.bookCount),
                Int64(sourceData.noteCount),
                Int64(sourceData.readingTimeCount)
            )
            isComplete = true
            state.status = .completedSupportedScope
            state.completedAt = Date()
            Self.saveState(state)
            // Keep legacy flag in sync once we have a truthful "supported scope completed" state.
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
        } catch {
            var state = Self.loadState()
                .flatMap { $0.matchesCurrentSource(at: flutterDBPath) ? $0 : nil }
                ?? PersistedMigrationState.new(for: flutterDBPath)
            state.status = .failed
            state.lastError = error.localizedDescription
            Self.saveState(state)

            errorMessage = migrationErrorMessage(for: error)
            statusMessage = localized("migration.status.failed")
        }
    }

    /// Skip migration and mark as done.
    public func skipMigration() {
        var state = Self.loadState()
            .flatMap { $0.matchesCurrentSource(at: flutterDBPath) ? $0 : nil }
            ?? PersistedMigrationState.new(for: flutterDBPath)
        state.status = .skipped
        state.completedAt = Date()
        Self.saveState(state)

        // Back-compat: older builds only check this boolean.
        UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
        isComplete = true
    }

    // MARK: - Private

    private static func loadState() -> PersistedMigrationState? {
        guard let data = UserDefaults.standard.data(forKey: migrationStateKey) else { return nil }
        return try? JSONDecoder().decode(PersistedMigrationState.self, from: data)
    }

    private static func saveState(_ state: PersistedMigrationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: migrationStateKey)
    }

    nonisolated static func validateLegacyDatabase(at url: URL) throws -> LegacyDatabaseMetadata {
        var configuration = Configuration()
        configuration.readonly = true
        let sourceDatabase = try DatabaseQueue(path: url.path, configuration: configuration)

        let metadata = try sourceDatabase.read { db in
            LegacyDatabaseMetadata(
                userVersion: try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0,
                tables: Set(
                    try String.fetchAll(
                        db,
                        sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'table'
                        """
                    )
                )
            )
        }

        guard metadata.userVersion <= expectedLegacySchemaVersion else {
            throw LegacyDatabasePreflightError.unsupportedSchema(metadata.userVersion)
        }

        let missingTables = requiredLegacyTables.subtracting(metadata.tables)
        guard missingTables.isEmpty else {
            throw LegacyDatabasePreflightError.missingRequiredTables(missingTables)
        }

        return metadata
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    private func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
        String(format: localized(key), locale: Locale.current, arguments: args)
    }

    private func migrationErrorMessage(for error: Error) -> String {
        switch error {
        case LegacyDatabasePreflightError.unsupportedSchema(let version):
            return localizedFormat(
                "migration.error.unsupported_schema",
                Int64(version),
                Int64(Self.expectedLegacySchemaVersion)
            )
        case LegacyDatabasePreflightError.missingRequiredTables(let missingTables):
            return localizedFormat(
                "migration.error.missing_required_tables",
                missingTables.sorted().joined(separator: ", ")
            )
        default:
            return localizedFormat("migration.error.failed_with_detail", error.localizedDescription)
        }
    }

    private struct PersistedMigrationState: Codable {
        enum Status: String, Codable {
            case notStarted
            case inProgress
            case completedSupportedScope
            case skipped
            case failed
        }

        enum Step: String, Codable, CaseIterable {
            case books
            case notes
            case readingTime
            case themes
            case styles
            case groups
            case tags
            case bookTags
            case memory
            case settings
        }

        struct Counts: Codable {
            var books: Int
            var notes: Int
            var readingTime: Int
        }

        struct SourceSignature: Codable, Equatable {
            var path: String
            var fileSize: Int64?
            var modificationTime: TimeInterval?

            static func from(fileURL: URL) -> SourceSignature {
                var fileSize: Int64?
                var modTime: TimeInterval?
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
                    if let size = attrs[.size] as? NSNumber {
                        fileSize = size.int64Value
                    }
                    if let date = attrs[.modificationDate] as? Date {
                        modTime = date.timeIntervalSince1970
                    }
                }
                return .init(path: fileURL.path, fileSize: fileSize, modificationTime: modTime)
            }
        }

        var schemaVersion: Int
        var status: Status
        var source: SourceSignature
        var completedSteps: Set<Step>
        var startedSteps: Set<Step>
        var lastObservedCounts: Counts?
        var lastError: String?
        var createdAt: Date
        var completedAt: Date?

        static func new(for sourceURL: URL) -> PersistedMigrationState {
            PersistedMigrationState(
                schemaVersion: 2,
                status: .notStarted,
                source: SourceSignature.from(fileURL: sourceURL),
                completedSteps: [],
                startedSteps: [],
                lastObservedCounts: nil,
                lastError: nil,
                createdAt: Date(),
                completedAt: nil
            )
        }

        var isFinished: Bool {
            switch status {
            case .completedSupportedScope, .skipped:
                return true
            case .notStarted, .inProgress, .failed:
                return false
            }
        }

        func matchesCurrentSource(at url: URL) -> Bool {
            source == .from(fileURL: url)
        }

        func markingStarted(_ step: Step) -> PersistedMigrationState {
            var copy = self
            copy.status = .inProgress
            copy.startedSteps.insert(step)
            return copy
        }

        func markingCompleted(_ step: Step) -> PersistedMigrationState {
            var copy = self
            copy.status = .inProgress
            copy.completedSteps.insert(step)
            return copy
        }
    }

    private struct FlutterData {
        let books: [Book]
        let notes: [BookNote]
        let readingTime: [ReadingTime]
        let themes: [ReadTheme]
        let styles: [BookStyle]
        let groups: [TbGroup]
        let tags: [Tag]
        let bookTags: [BookTag]
        var bookCount: Int { books.count }
        var noteCount: Int { notes.count }
        var readingTimeCount: Int { readingTime.count }
    }

    private func readFlutterDatabase() throws -> FlutterData {
        var configuration = Configuration()
        configuration.readonly = true
        let sourceDatabase = try DatabaseQueue(path: flutterDBPath.path, configuration: configuration)

        return try sourceDatabase.read { db in
            FlutterData(
                books: try Book
                    .filter(Column("is_deleted") == false)
                    .fetchAll(db),
                notes: try BookNote.fetchAll(db),
                readingTime: try ReadingTime.fetchAll(db),
                themes: try ReadTheme.fetchAll(db),
                styles: try BookStyle.fetchAll(db),
                groups: try TbGroup.fetchAll(db),
                tags: try Tag.fetchAll(db),
                bookTags: try BookTag.fetchAll(db)
            )
        }
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
    func migrateFlutterBooks(_ books: [Book]) async throws {
        guard books.isEmpty == false else { return }
        try await writer.write { db in
            // `writer.write` runs in a transaction by default (atomic per step).
            for book in books {
                try book.save(db)
            }
        }
    }

    /// Import notes from Flutter DB rows.
    func migrateFlutterNotes(_ notes: [BookNote]) async throws {
        guard notes.isEmpty == false else { return }
        try await writer.write { db in
            // `writer.write` runs in a transaction by default (atomic per step).
            for note in notes {
                try note.save(db)
            }
        }
    }

    /// Import reading time records from Flutter DB rows.
    func migrateFlutterReadingTime(_ records: [ReadingTime]) async throws {
        guard records.isEmpty == false else { return }
        try await writer.write { db in
            // `writer.write` runs in a transaction by default (atomic per step).
            for record in records {
                try record.save(db)
            }
        }
    }

    func migrateFlutterThemes(_ themes: [ReadTheme]) async throws {
        guard themes.isEmpty == false else { return }
        try await writer.write { db in
            for theme in themes {
                try theme.save(db)
            }
        }
    }

    func migrateFlutterStyles(_ styles: [BookStyle]) async throws {
        guard styles.isEmpty == false else { return }
        try await writer.write { db in
            for style in styles {
                try style.save(db)
            }
        }
    }

    func migrateFlutterGroups(_ groups: [TbGroup]) async throws {
        guard groups.isEmpty == false else { return }
        try await writer.write { db in
            for group in groups {
                try group.save(db)
            }
        }
    }

    func migrateFlutterTags(_ tags: [Tag]) async throws {
        guard tags.isEmpty == false else { return }
        try await writer.write { db in
            for tag in tags {
                try tag.save(db)
            }
        }
    }

    func migrateFlutterBookTags(_ bookTags: [BookTag]) async throws {
        guard bookTags.isEmpty == false else { return }
        try await writer.write { db in
            for bookTag in bookTags {
                try bookTag.save(db)
            }
        }
    }
}
