import Foundation
import GRDB
import Testing
@testable import PaperTokReader

@Suite("FlutterMigrationService")
struct FlutterMigrationServiceTests {
    @Test("legacy migration accepts older schema versions when required tables are present")
    func acceptsOlderSchemaVersions() throws {
        let databaseURL = try makeLegacyDatabase(
            userVersion: FlutterMigrationService.expectedLegacySchemaVersion - 1,
            tableNames: FlutterMigrationService.requiredLegacyTables
        )
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let metadata = try FlutterMigrationService.validateLegacyDatabase(at: databaseURL)
        #expect(metadata.userVersion == FlutterMigrationService.expectedLegacySchemaVersion - 1)
        #expect(metadata.tables == FlutterMigrationService.requiredLegacyTables)
    }

    @Test("legacy migration rejects future schema versions before importing")
    func rejectsFutureSchemaVersions() throws {
        let databaseURL = try makeLegacyDatabase(
            userVersion: FlutterMigrationService.expectedLegacySchemaVersion + 1,
            tableNames: FlutterMigrationService.requiredLegacyTables
        )
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        do {
            _ = try FlutterMigrationService.validateLegacyDatabase(at: databaseURL)
            Issue.record("Expected unsupported schema version to be rejected")
        } catch let error as FlutterMigrationService.LegacyDatabasePreflightError {
            switch error {
            case .unsupportedSchema(let version):
                #expect(version == FlutterMigrationService.expectedLegacySchemaVersion + 1)
            default:
                Issue.record("Expected unsupportedSchema error, got \(error)")
            }
        }
    }

    @Test("legacy migration rejects databases missing required tables")
    func rejectsMissingRequiredTables() throws {
        let tableNames = Set(FlutterMigrationService.requiredLegacyTables.dropLast())
        let databaseURL = try makeLegacyDatabase(
            userVersion: FlutterMigrationService.expectedLegacySchemaVersion,
            tableNames: tableNames
        )
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        do {
            _ = try FlutterMigrationService.validateLegacyDatabase(at: databaseURL)
            Issue.record("Expected missing legacy tables to be rejected")
        } catch let error as FlutterMigrationService.LegacyDatabasePreflightError {
            switch error {
            case .missingRequiredTables(let missingTables):
                #expect(missingTables == FlutterMigrationService.requiredLegacyTables.subtracting(tableNames))
            default:
                Issue.record("Expected missingRequiredTables error, got \(error)")
            }
        }
    }

    private func makeLegacyDatabase(userVersion: Int, tableNames: Set<String>) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlutterMigrationService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("anx_reader.db")
        let queue = try DatabaseQueue(path: databaseURL.path)

        try queue.write { db in
            for tableName in tableNames.sorted() {
                try db.execute(sql: "CREATE TABLE \(tableName) (id INTEGER PRIMARY KEY)")
            }
            try db.execute(sql: "PRAGMA user_version = \(userVersion)")
        }

        return databaseURL
    }
}
