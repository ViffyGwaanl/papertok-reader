import Foundation
import Testing
import PTAIServices

@Suite("Migration localization catalog")
struct MigrationLocalizationCatalogTests {
    @Test("catalog contains critical Swift Native localization keys with Chinese coverage")
    func catalogContainsCriticalKeys() throws {
        let strings = try catalogStrings()

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
            "migration.error.failed",
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
            "intent.open_book.dialog_format",
            "intent.send_message.title",
            "intent.send_message.description",
            "intent.send_message.parameter.message",
            "intent.send_message.parameter.images",
            "intent.search_books.title",
            "intent.search_books.description",
            "intent.search_books.error.empty_query",
            "intent.search_books.no_matches_format",
            "intent.search_books.dialog.results_format",
            "intent.get_stats.title",
            "intent.get_stats.description",
            "intent.get_stats.scope.type",
            "intent.get_stats.summary.reading_time.today_format",
            "intent.get_stats.summary.reading_time.week_format",
            "intent.get_stats.summary.reading_time.month_format",
            "intent.get_stats.summary.reading_time.all_format",
            "intent.get_stats.summary.books_count_format",
            "intent.get_stats.summary.notes_count_format",
            "intent.get_stats.summary.streak_format",
            "intent.get_stats.dialog.today_format",
            "intent.get_stats.dialog.week_format",
            "intent.get_stats.dialog.month_format",
            "intent.get_stats.dialog.all_format",
            "intent.create_note.error.book_not_found_format",
            "intent.create_note.summary_format",
            "intent.create_note.dialog_format",
            "intent.multi_step.error.missing_parameter_format",
            "intent.multi_step.error.step_failed_format",
            "intent.multi_step.error.unsupported_intent_format",
            "intent.shortcut.open_book.phrase.open",
            "intent.shortcut.open_book.phrase.read",
            "intent.shortcut.ask_ai.phrase.ask",
            "intent.shortcut.ask_ai.phrase.chat",
            "intent.shortcut.send_message.phrase.message",
            "intent.shortcut.send_message.phrase.images",
            "intent.shortcut.search_books.phrase.search",
            "intent.shortcut.search_books.phrase.find",
            "intent.shortcut.get_stats.phrase.stats",
            "intent.shortcut.get_stats.phrase.time",
            "intent.shortcut.create_note.phrase.create",
            "intent.shortcut.create_note.phrase.add",
            "Open a book in ${applicationName}",
            "Read with ${applicationName}",
            "Ask ${applicationName} a question",
            "Chat with ${applicationName}",
            "Send a message to ${applicationName}",
            "Send images to ${applicationName}",
            "Search books in ${applicationName}",
            "Find a book in ${applicationName}",
            "Get my reading stats from ${applicationName}",
            "Show reading time in ${applicationName}",
            "Create a note in ${applicationName}",
            "Add a book note to ${applicationName}",
            "notes.book_fallback_format",
            "notes.sort_chapter",
            "notes.empty.filtered_title_format",
            "notes.empty.search_description",
            "notes.empty.filtered_description_format",
            "notes.editor",
            "notes.preview",
            "notes.link",
            "notes.heading",
            "notes.export.title",
            "notes.export.total_notes_format",
            "notes.export.books_with_notes_format",
            "notes.export.chapter_format",
            "notes.export.note_format",
            "notes.export.type.markdown",
            "notes.export.type.csv",
            "notes.export.type.txt",
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
            "ai.chat.system_prompt_default",
            "ai.chat_settings.temperature_hint",
            "ai.chat_settings.max_tokens_hint",
            "ai.chat_settings.top_p_hint",
            "ai.chat_settings.per_conversation",
            "ai.chat_settings.per_conversation_footer",
            "ai.chat_settings.global_footer",
            "ai.tool.result_title",
            "common.default",
            "common.strict",
            "common.relaxed",
            "common.minimal",
            "common.low",
            "common.medium",
            "common.high",
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
            "ai.chat.attachment_file_format",
            "bookshelf.edit.empty_title_required",
            "bookshelf.edit.book_not_found",
            "bookshelf.edit.operation_failed",
            "bookshelf.tag.operation_failed",
            "bookshelf.group.operation_failed",
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
            "settings.ai_provider.delete_confirmation",
            "settings.ai_provider.delete_provider",
            "settings.ai_provider.manage_api_keys",
            "settings.ai_provider.api_keys",
            "settings.ai_provider.api_keys_count_format",
            "settings.ai_provider.api_keys_footer",
            "settings.ai_provider.azure_deployment_name",
            "settings.ai_provider.azure_api_version",
            "settings.ai_provider.max_tokens",
            "settings.ai_provider.stop_sequences",
            "settings.ai_provider.generation_defaults",
            "settings.ai_provider.generation_defaults_footer",
            "settings.ai_provider.gemini_options",
            "settings.ai_provider.include_thinking_steps",
            "settings.ai_provider.safety_settings",
            "settings.ai_provider.reasoning",
            "settings.ai_provider.reasoning_effort",
            "settings.ai_provider.return_reasoning_summary",
            "settings.ai_provider.use_previous_response_id",
            "settings.ai_provider.failure_threshold",
            "settings.ai_provider.auth_cooldown",
            "settings.ai_provider.rate_limit_cooldown",
            "settings.ai_provider.service_cooldown",
            "settings.ai_provider.failover_policy",
            "settings.ai_provider.failover_policy_footer",
            "settings.developer.verbose_logging",
            "settings.storage.database",
            "settings.storage.history_cleared",
            "settings.home_nav.reset_confirmation",
            "tab.papers",
            "tab.bookshelf",
            "tab.notes",
            "tab.statistics",
            "tab.ai",
            "tab.settings",
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
            "reader.brightness",
            "reader.opening_ellipsis",
            "reader.page_number_format",
            "reader.pages_range_format",
            "reader.search_contents",
            "reader.search_this_pdf",
            "reader.search_failed_title",
            "reader.search.no_results_title",
            "reader.preparing_search_ellipsis",
            "reader.section_number_format",
            "reader.toc.empty_title",
            "reader.toc.match_count_format",
            "reader.cannot_open_title",
            "reader.volume_keys_turn_pages",
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
            "prompts.icon_emoji_placeholder",
            "prompts.tap_to_edit",
            "prompts.untitled",
            "prompts.new",
            "prompts.edit",
            "papers.empty.failed_to_load",
            "papers.empty.no_papers",
            "papers.download.phase.downloading",
            "papers.download.phase.importing",
            "notes.pdf.header.author_format",
            "notes.pdf.header.exported_at_format",
            "notes.pdf.footer.page_format",
            "errors.reader.export_highlights_failed_format",
            "errors.reader.annotation_load_failed",
            "errors.reader.annotation_delete_failed",
            "errors.reader.selected_text_required",
            "errors.tts.load_voices_failed_format",
            "errors.translation.failed",
            "errors.translation.not_configured",
            "errors.backup.zip_failed",
            "errors.backup.unzip_failed",
            "errors.ai.selected_provider_unavailable",
            "errors.ai.selected_model_unavailable",
            "errors.ai.pending_tool_approvals",
            "errors.ai.tool_round_limit_format",
            "errors.ai.unknown_tool_format",
            "errors.ai.tool_denied",
            "errors.ai.tool_failed",
            "errors.ai.content_filtered",
            "errors.ai.service_unavailable",
            "errors.ai.unsupported_capability",
            "errors.network.no_data",
            "errors.network.connection_lost",
            "errors.network.invalid_url",
            "errors.network.decoding_failed",
            "errors.papers.detail_unavailable",
            "errors.papers.no_downloadable_file",
            "errors.calendar.access_denied",
            "errors.calendar.event_not_found_format",
            "errors.reminders.access_denied",
            "errors.reminders.not_found_format",
            "prompts.reset_confirmation",
            "prompts.duplicate_title_format",
            "prompts.title_placeholder",
            "ai.providers.custom_name_placeholder",
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

    @Test("audited Swift Native closure files have catalog entries with Chinese coverage")
    func auditedFilesHaveCatalogCoverage() throws {
        let strings = try catalogStrings()
        let keys = try extractedLocalizationKeys(
            from: [
                "App/ContentView.swift",
                "App/Extensions/ShareExtension/DOCXExtractor.swift",
                "App/Platform/AI/ShortcutAIService.swift",
                "App/Platform/DeepLink/ReaderLocatorResolver.swift",
                "App/Platform/Migration/FlutterMigrationService.swift",
                "App/Platform/Migration/MigrationProgressView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Navigation/AppTab.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesSupport.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/RichNoteEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ChatSettingsSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ConversationListView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageBubbleView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ExcerptMenuSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/TranslationMenuSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderControlsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderAnnotationsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/HighlightExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderAIQuickActionsSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIImageAnalysisView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderCenterView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/ReadingDetailSettingsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIToolsConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/MCPConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PapersView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadWorker.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Statistics/CompletionTrackingView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/BackupService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/ConnectionTesterView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesPDFExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/KAIROS/KAIROSService.swift",
                "Packages/PTReader/Sources/PTReader/EPUB/EPUBPublicationOpener.swift",
                "Packages/PTReader/Sources/PTReader/EPUB/EPUBContentBridge.swift",
                "Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift",
                "App/Platform/Intents/OpenBookIntent.swift",
                "App/Platform/Intents/SearchBooksIntent.swift",
                "App/Platform/Intents/GetReadingStatsIntent.swift",
                "App/Platform/Intents/CreateNoteIntent.swift",
                "App/Platform/Intents/IntentsDonationService.swift",
                "Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkError.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPClient.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPTransport.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Tools/ToolOrchestrator.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Providers/ProviderError.swift",
            ]
        )

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "Missing catalog entry for \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "\(key) missing localizations")
            for locale in ["zh-Hans", "zh-Hant"] {
                let localization = try #require(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "\(key) missing stringUnit for \(locale)")
                let value = try #require(stringUnit["value"] as? String, "\(key) missing value for \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("app shortcut phrases have dedicated catalog coverage")
    func appShortcutPhrasesHaveDedicatedCatalogCoverage() throws {
        let strings = try appShortcutCatalogStrings()
        let phrases = try extractedAppShortcutPhrases(from: "App/Platform/Intents/IntentsDonationService.swift")

        for phrase in phrases {
            let entry = try #require(strings[phrase] as? [String: Any], "Missing AppShortcuts catalog entry for \(phrase)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "\(phrase) missing localizations")
            for locale in ["zh-Hans", "zh-Hant"] {
                let localization = try #require(localizations[locale] as? [String: Any], "\(phrase) missing \(locale)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "\(phrase) missing stringUnit for \(locale)")
                let value = try #require(stringUnit["value"] as? String, "\(phrase) missing value for \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("built-in AI tool display keys have Chinese catalog coverage")
    func builtInAIToolDisplayKeysHaveCatalogCoverage() throws {
        let strings = try catalogStrings()
        let keys = Set(
            ToolRegistry().allTools.flatMap { tool in
                let rawName = type(of: tool).name
                return [
                    AIToolPresentation.nameKey(for: rawName),
                    AIToolPresentation.descriptionKey(for: rawName),
                ]
            }
        )

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "Missing catalog entry for \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "\(key) missing localizations")
            for locale in ["zh-Hans", "zh-Hant"] {
                let localization = try #require(localizations[locale] as? [String: Any], "\(key) missing \(locale)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "\(key) missing stringUnit for \(locale)")
                let value = try #require(stringUnit["value"] as? String, "\(key) missing value for \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func catalogStrings() throws -> [String: Any] {
        try mergedCatalogStrings(named: ["Localizable.xcstrings", "AppShortcuts.xcstrings"])
    }

    private func appShortcutCatalogStrings() throws -> [String: Any] {
        try mergedCatalogStrings(named: ["AppShortcuts.xcstrings"])
    }

    private func mergedCatalogStrings(named fileNames: [String]) throws -> [String: Any] {
        var merged: [String: Any] = [:]

        for fileName in fileNames {
            let catalogURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("App", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(fileName)

            let catalogData = try Data(contentsOf: catalogURL)
            let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
            let strings = try #require(catalog["strings"] as? [String: Any])
            merged.merge(strings) { current, _ in current }
        }

        return merged
    }

    private func extractedLocalizationKeys(from files: [String]) throws -> [String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let patterns = [
            #"String\(localized:\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"Text\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)"\s*\)"#,
            #"(?:TextField|SecureField|Picker|Toggle|Section|Label|Button|ContentUnavailableView|Menu|PTChip|SharePreview|ProgressView)\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\.(?:navigationTitle|confirmationDialog|alert|accessibilityLabel)\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"Button\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"Label\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\blocalized\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\bformat\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\blocalizedCatalogString\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\blocalizedCatalogFormat\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\baiChatLocalizedCatalogString\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"\baiChatLocalizedCatalogFormat\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"AppLocalization\.string\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"AppLocalization\.format\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"fallbackKey:\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
            #"NSLocalizedString\(\s*"([a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+)""#,
        ].map { try! NSRegularExpression(pattern: $0) }

        var keys = Set<String>()
        for relativePath in files {
            let text = try String(contentsOf: repoRoot.appendingPathComponent(relativePath))
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            for regex in patterns {
                for match in regex.matches(in: text, range: range) {
                    let key = nsText.substring(with: match.range(at: 1))
                    keys.insert(key)
                }
            }
        }

        return keys.sorted()
    }

    private func extractedAppShortcutPhrases(from file: String) throws -> [String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let text = try String(contentsOf: repoRoot.appendingPathComponent(file))
        let nsText = text as NSString
        let regex = try NSRegularExpression(pattern: #"AppShortcutPhrase<[^>]+>\("([^"]+)"\)"#)
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: text, range: range).map { match in
            let phrase = nsText.substring(with: match.range(at: 1))
            return phrase.replacingOccurrences(of: #"\(.applicationName)"#, with: "${applicationName}")
        }
    }
}
