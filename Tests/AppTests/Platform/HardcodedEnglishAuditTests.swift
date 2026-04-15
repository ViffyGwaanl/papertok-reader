import Foundation
import Testing

@Suite("Hardcoded English audit")
struct HardcodedEnglishAuditTests {
    @Test("audited Swift Native UI files do not contain bare English UI literals")
    func auditedUIFilesAvoidBareEnglish() throws {
        let violations = try scan(
            files: [
                "App/ContentView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Navigation/AppTab.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/RichNoteEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AILibraryIndexView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/APIKeyListView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/DeveloperOptionsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/SyncSettingsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/QuickPromptsEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/StorageManagementView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/HomeNavigationConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/MCPConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/ReadingDetailSettingsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ChatInputView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ChatSettingsSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ConversationListView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageBubbleView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Memory/MemoryHomeView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/State/ReaderStateScreen.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderSettingsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/CustomFontPicker.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/BookmarkManagerView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ContextMenuAction.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ExcerptMenuSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/NoteEditorSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/AnnotationStylePicker.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ReaderContextMenuView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/TTSFloatingActionButton.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/DictionaryLookupSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderAIPanelHost.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderAIQuickActionsSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/AIContext/ReaderContextResolver.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/AIContext/EPUBReaderContextResolver.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/AIContext/PDFReaderContextResolver.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageViewer.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/Search/ReaderFindBar.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/Search/ReaderFindBarState.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PapersFilterBar.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PapersView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/ConnectionTesterView.swift",
                "App/Platform/macOS/MacMenuCommands.swift",
                "App/Platform/Intents/OpenBookIntent.swift",
                "App/Platform/Intents/SearchBooksIntent.swift",
                "App/Platform/Intents/GetReadingStatsIntent.swift",
                "App/Platform/Intents/CreateNoteIntent.swift",
                "App/Platform/Intents/IntentsDonationService.swift",
            ],
            rules: [
                RegexRule(
                    description: "bare English UI literal",
                    pattern: #"(?:TextField|SecureField|Picker|Toggle|Section|Label|Button|ContentUnavailableView|Menu|PTChip|SharePreview|navigationTitle|confirmationDialog|alert|ProgressView|accessibilityLabel)\(\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English placeholder literal",
                    pattern: #"placeholder:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English text literal",
                    pattern: #"\bText\(\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English helper title literal",
                    pattern: #"\btitle:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*""#
                ),
                RegexRule(
                    description: "bare English helper hint literal",
                    pattern: #"\bhint:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*""#
                ),
                RegexRule(
                    description: "bare English help literal",
                    pattern: #"\.help\(\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*""#
                ),
                RegexRule(
                    description: "bare English fallback literal",
                    pattern: #"\?\?\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*""#
                ),
                RegexRule(
                    description: "bare English app intent title literal",
                    pattern: #"static\s+let\s+title:\s*LocalizedStringResource\s*=\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English intent description literal",
                    pattern: #"IntentDescription\(\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English intent parameter literal",
                    pattern: #"@Parameter\(title:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English intent dialog literal",
                    pattern: #"(?:dialog:\s*|IntentDialog\s*=\s*)"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English shortcut title literal",
                    pattern: #"\bshortTitle:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English shortcut phrase literal",
                    pattern: #"(?m)^\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*"(?:,)?$"#
                ),
                RegexRule(
                    description: "bare English AppLocalization fallback",
                    pattern: #"AppLocalization\.(?:string|format)\(\s*"[A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+"\s*,\s*(?:value:\s*)?"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Z][^"]*""#
                ),
                RegexRule(
                    description: "bare English capability badge array",
                    pattern: #"\[\s*(?:"[A-Z]{2,}"\s*,\s*)+"[A-Z]{2,}"\s*\]"#
                ),
                RegexRule(
                    description: "bare English duration option literal",
                    pattern: #"\(\s*\d+\s*,\s*"\d+\s+(?:min|hour|hours)"\s*\)"#
                ),
            ],
            allowlistFragments: [
                #"return "OpenAI""#,
                #"return "Azure""#,
                #" ? "EPUB" : "PDF""#,
                #"return "square.grid.2x2""#,
                #"return "list.bullet""#,
                #"AppShortcutPhrase<"#,
                #""System","#,
                #""Times New Roman","#,
                #""Helvetica Neue","#,
                #""Avenir","#,
                #""Avenir Next","#,
                #""Charter","#,
                #""New York","#,
                #""Menlo","#,
                #""Courier New","#,
            ]
        )

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    @Test("audited user-visible error files do not return bare English messages")
    func auditedErrorFilesAvoidBareEnglish() throws {
        let violations = try scan(
            files: [
                "App/Extensions/ShareExtension/DOCXExtractor.swift",
                "App/ContentView.swift",
                "App/Platform/Migration/FlutterMigrationService.swift",
                "App/Platform/Share/SharedInboxImportProcessor.swift",
                "App/Platform/AI/ShortcutAIService.swift",
                "App/Platform/DeepLink/ReaderLocatorResolver.swift",
                "App/Platform/EventKit/CalendarService.swift",
                "App/Platform/EventKit/RemindersService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Bookshelf/AIOrganizeService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ConversationListView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesPDFExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/AISettingsSyncService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/IncrementalSyncEngine.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/BackupService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/ConnectionTesterView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/WebDAVSyncService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Memory/MemoryHomeViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderAnnotationsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderControlsViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageViewer.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/TranslationMenuSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/MCPConfigView.swift",
                "Packages/PTReader/Sources/PTReader/EPUB/EPUBPublicationOpener.swift",
                "Packages/PTReader/Sources/PTReader/EPUB/EPUBReaderView.swift",
                "Packages/PTReader/Sources/PTReader/EPUB/EPUBContentBridge.swift",
                "Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkError.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryWorkflowService.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryCandidateStore.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPClient.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPMessage.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPConfiguration.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPTransport.swift",
                "Packages/PTAIServices/Sources/PTAIServices/RAG/EmbeddingService.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryIndexDatabase.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/SessionDigestService.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Tools/ToolOrchestrator.swift",
                "Packages/PTCore/Sources/PTCore/Localization/AppLocalization.swift",
            ],
            rules: [
                RegexRule(
                    description: "bare English error return",
                    pattern: #"(?:return|errorMessage\s*=)\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "raw localizedDescription reaches user-visible state",
                    pattern: #"(?:errorMessage|tocErrorMessage|searchErrorMessage|loadError)\s*=\s*error\.localizedDescription|errorMessage:\s*error\.localizedDescription|AppLocalization\.format\([^\n]*error\.localizedDescription|return\s+AppLocalization\.format\([^\n]*error\.localizedDescription"#
                ),
                RegexRule(
                    description: "bare English AppLocalization userFacingErrorMessage fallback",
                    pattern: #"AppLocalization\.userFacingErrorMessage\([^\n]*fallback:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English attachment placeholder",
                    pattern: #"\[Attached file:"#
                ),
            ],
            allowlistFragments: [
                "return \"#808080\"",
                #"return "\(trimmed)/\(remoteFilename)""#,
                #"return "- id=\(id) | "#,
                #"return "zh-Hant""#,
                #"return "zh-Hans""#,
                #"return "en""#,
                #"return "image/jpeg""#,
                #"return "image/gif""#,
                #"return "image/webp""#,
                #"return "image/heic""#,
                #"return "image/png""#,
                #"return "magnifyingglass""#,
                #"return "bookmark.fill""#,
                #"return "text.bubble.fill""#,
                #"return "highlighter""#,
                #"return "circle""#,
                #"return "hourglass""#,
                #"return "checkmark.circle.fill""#,
                #"return "xmark.circle.fill""#,
            ]
        )

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    @Test("audited formatter files do not build bare English user-visible output")
    func auditedFormatterFilesAvoidBareEnglishOutput() throws {
        let violations = try scan(
            files: [
                "Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesSupport.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesPDFExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadWorker.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/HighlightExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageAnalysisPrompt.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ContextMenuCoordinator.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift",
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/MemoryView.swift",
                "Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryDocumentLocalization.swift",
                "Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryContextBuilder.swift",
            ],
            rules: [
                RegexRule(
                    description: "bare English output literal",
                    pattern: #"(?:return|out \+=|title:\s*)\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English attributed string literal",
                    pattern: #"NSAttributedString\(string:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English single-expression switch literal",
                    pattern: #"case\s+\.[a-zA-Z0-9_]+:\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English memory seed header literal",
                    pattern: ##"content\s*=\s*"#\s*[A-Za-z][^"]*""##
                ),
            ],
            allowlistFragments: [
                #"return "E8D890""#,
                #"return "D09898""#,
                #"return "B898C8""#,
                #"return "translation""#,
                #"return "excerpt""#,
                #"return "note""#,
                #"return "dictionary""#,
                #"return "noteEdit-\(id)""#,
            ]
        )

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    @Test("remaining localization closure files avoid helper fallbacks and hardcoded English badges")
    func closureFilesAvoidHelperFallbacks() throws {
        let violations = try scan(
            files: [
                "Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderCenterView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIToolsConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIImageAnalysisView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Statistics/CompletionTrackingView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/KAIROS/KAIROSService.swift",
            ],
            rules: [
                RegexRule(
                    description: "localized helper fallback literal",
                    pattern: #"\blocalized\(\s*"[A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+"\s*,\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z%][^"]*""#
                ),
                RegexRule(
                    description: "format helper fallback literal",
                    pattern: #"\bformat\(\s*"[A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+"\s*,\s*"(?![A-Za-z0-9_.-]+(?:\.[A-Za-z0-9_.-]+)+")[A-Za-z%][^"]*""#
                ),
                RegexRule(
                    description: "hardcoded provider capability badge array",
                    pattern: #"\[\s*(?:"[A-Z]{2,}"\s*,\s*)+"[A-Z]{2,}"\s*\]"#
                ),
                RegexRule(
                    description: "hardcoded rawValue uppercased badge",
                    pattern: #"\.rawValue\.uppercased\(\)"#
                ),
                RegexRule(
                    description: "parenthesized default literal",
                    pattern: #""\(default\)""#
                ),
            ],
            allowlistFragments: []
        )

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    private func scan(
        files: [String],
        rules: [RegexRule],
        allowlistFragments: Set<String>
    ) throws -> [String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var violations: [String] = []

        for relativePath in files {
            let fileURL = repoRoot.appendingPathComponent(relativePath)
            let text = try String(contentsOf: fileURL)
            let nsText = text as NSString

            for rule in rules {
                let matches = rule.regex.matches(
                    in: text,
                    options: [],
                    range: NSRange(location: 0, length: nsText.length)
                )

                for match in matches {
                    let lineRange = nsText.lineRange(for: match.range)
                    let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if allowlistFragments.contains(where: { line.contains($0) }) {
                        continue
                    }

                    let lineNumber = nsText.substring(to: match.range.location)
                        .reduce(into: 1) { count, character in
                            if character == "\n" { count += 1 }
                        }
                    violations.append("\(relativePath):\(lineNumber): \(rule.description): \(line)")
                }
            }
        }

        return violations.sorted()
    }
}

private struct RegexRule {
    let description: String
    let regex: NSRegularExpression

    init(description: String, pattern: String) {
        self.description = description
        self.regex = try! NSRegularExpression(pattern: pattern)
    }
}
