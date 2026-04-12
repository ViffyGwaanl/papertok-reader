import Foundation
import Testing

@Suite("Migration localization catalog")
struct MigrationLocalizationCatalogTests {
    @Test("catalog contains migration status and error keys used by the service")
    func catalogContainsWave4Keys() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localizable.xcstrings")

        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])

        let requiredKeys: Set<String> = [
            "migration.status.preparing",
            "migration.status.reading_bookshelf",
            "migration.status.migrating_books_count",
            "migration.status.migrating_notes",
            "migration.status.migrating_reading_records",
            "migration.status.migrating_themes",
            "migration.status.migrating_styles",
            "migration.status.migrating_groups",
            "migration.status.migrating_tags",
            "migration.status.migrating_book_tags",
            "migration.status.migrating_memory",
            "migration.status.migrating_settings",
            "migration.status.complete_summary",
            "migration.status.failed",
            "migration.status.legacy_done",
            "migration.error.db_not_found",
            "migration.error.failed_with_detail",
            "migration.error.unsupported_schema",
            "migration.error.missing_required_tables",
            "migration.warning.api_keys_not_migrated",
            "share.error.content_unavailable",
            "share.error.route_requires_bookshelf",
            "share.ai_prompt.image_analysis",
            "share.ai_prompt.content_analysis",
            "intent.ask_ai.title",
            "intent.ask_ai.description",
            "intent.ask_ai.parameter.question",
            "intent.open_book.title",
            "intent.open_book.description",
            "intent.open_book.parameter.book_title",
            "intent.send_message.title",
            "intent.send_message.description",
            "intent.send_message.parameter.message",
            "intent.send_message.parameter.images",
        ]

        #expect(requiredKeys.isSubset(of: Set(strings.keys)))
    }
}
