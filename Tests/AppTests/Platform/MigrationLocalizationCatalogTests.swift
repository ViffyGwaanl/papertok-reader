import Foundation
import Testing

@Suite("Migration localization catalog")
struct MigrationLocalizationCatalogTests {
    @Test("catalog contains critical Swift Native localization keys with Chinese coverage")
    func catalogContainsCriticalKeys() throws {
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
            "notes.book_fallback_format",
            "notes.empty.filtered_title_format",
            "notes.empty.search_description",
            "notes.empty.filtered_description_format",
            "notes.link",
            "notes.heading",
            "papers.import_epub",
            "papers.import_pdf",
            "papers.download.starting",
            "papers.download.saving_to_bookshelf",
            "papers.search_placeholder",
            "papers.explanation",
            "papers.dialogue",
            "ai.search_conversations",
            "ai.conversations.pinned",
            "ai.stop_sequences_placeholder",
            "common.yesterday",
            "common.this_week",
            "common.earlier",
            "common.password",
            "common.failed_to_load",
            "common.full_screen",
            "common.exit_full_screen",
            "common.minimize",
            "common.import",
            "common.enabled",
            "common.unknown",
            "common.untitled",
            "common.disconnected",
            "common.connecting_ellipsis",
            "common.connected_tool_count_format",
            "common.error_detail_format",
            "sync.connection_status.success",
            "sync.connection_status.failure",
            "sync.conflict_description.last_modified_wins",
            "sync.conflict_description.local_wins",
            "sync.conflict_description.remote_wins",
            "sync.conflict_description.manual",
            "sync.run_test",
            "sync.connection_check.reachability",
            "sync.connection_check.authentication",
            "sync.connection_check.write_permission",
            "sync.connection_check.latency",
            "sync.connection_check.quota",
            "sync.connection_detail.not_configured",
            "sync.connection_detail.configure_webdav_first",
            "sync.connection_detail.all_passed",
            "sync.connection_detail.summary_failed",
            "sync.connection_detail.server_reachable",
            "sync.connection_detail.reachability_failed_format",
            "sync.connection_detail.credentials_accepted",
            "sync.connection_detail.auth_failed_format",
            "sync.connection_detail.write_ok",
            "sync.connection_detail.cannot_write_format",
            "sync.connection_detail.latency_probe_failed",
            "sync.connection_detail.latency_average",
            "sync.connection_detail.quota_unavailable",
            "sync.connection_detail.quota_failed_format",
            "settings.ai_library.title",
            "settings.ai_library.embedding_provider",
            "settings.ai_library.embedding_model",
            "settings.ai_library.index_all_books",
            "settings.ai_library.clear_all_indexes",
            "settings.ai_library.indexed_chunks_format",
            "settings.api_keys.title",
            "settings.api_keys.bulk_import_title",
            "settings.api_keys.status.ok_relative_format",
            "settings.developer.verbose_logging",
            "settings.storage.database",
            "settings.storage.history_cleared",
            "settings.home_nav.reset_confirmation",
            "reader.quick_action.explain.title",
            "reader.quick_action.explain.subtitle",
            "reader.quick_action.translate.title",
            "reader.quick_action.translate.subtitle",
            "reader.quick_action.summarize.title",
            "reader.quick_action.summarize.subtitle",
            "reader.quick_action.define_vocabulary.title",
            "reader.quick_action.define_vocabulary.subtitle",
            "reader.quick_action.explain.prompt.chapter",
            "reader.quick_action.explain.prompt.book",
            "reader.quick_action.translate.prompt.chapter",
            "reader.quick_action.translate.prompt.book",
            "reader.quick_action.summarize.prompt.chapter",
            "reader.quick_action.summarize.prompt.book",
            "reader.quick_action.define_vocabulary.prompt.chapter",
            "reader.quick_action.define_vocabulary.prompt.book",
            "reader.bookmarks",
            "reader.bookmarks_empty_title",
            "reader.search_this_pdf",
            "reader.cannot_open_title",
            "reader.dictionary.no_definition_title",
            "reader.ai_panel.pending_approval",
            "reader.ai_panel.pending_approvals_format",
            "reader.annotation.add",
            "reader.appearance.theme_light",
            "reader.appearance.theme_dark",
            "reader.appearance.theme_sepia",
            "reader.appearance.theme_custom",
            "reader.appearance.font_size",
            "reader.appearance.line_height",
            "reader.appearance.letter_spacing",
            "reader.appearance.word_spacing",
            "reader.appearance.paragraph_spacing",
            "reader.appearance.side_margin",
            "reader.appearance.top_margin",
            "reader.appearance.bottom_margin",
            "reader.appearance.preview_sentence",
            "errors.reader.export_highlights_failed_format",
            "errors.tts.load_voices_failed_format",
            "errors.network.no_data",
            "errors.network.connection_lost",
            "errors.papers.detail_unavailable",
            "errors.papers.no_downloadable_file",
            "prompts.reset_confirmation",
            "prompts.duplicate_title_format",
            "prompts.title_placeholder",
        ]

        #expect(requiredKeys.isSubset(of: Set(strings.keys)))

        for key in requiredKeys {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for locale in ["zh-Hans", "zh-Hant"] {
                let localization = try #require(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "\(key) missing stringUnit for \(locale)")
                let value = try #require(stringUnit["value"] as? String, "\(key) missing value for \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
