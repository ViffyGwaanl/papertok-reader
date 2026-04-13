import Foundation
import Testing

@Suite("Hardcoded English audit")
struct HardcodedEnglishAuditTests {
    @Test("audited Swift Native UI files do not contain bare English UI literals")
    func auditedUIFilesAvoidBareEnglish() throws {
        let violations = try scan(
            files: [
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AILibraryIndexView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/APIKeyListView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/DeveloperOptionsView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/QuickPromptsEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/StorageManagementView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/HomeNavigationConfigView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Settings/AIProviderDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/BookmarkManagerView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/ContextMenuAction.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/TTSFloatingActionButton.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/DictionaryLookupSheet.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderAIPanelHost.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationEditorView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Papers/PapersFilterBar.swift",
            ],
            rules: [
                RegexRule(
                    description: "bare English UI literal",
                    pattern: #"(?:TextField|SecureField|Picker|Toggle|Section|Label|Button|ContentUnavailableView|navigationTitle|confirmationDialog|alert|ProgressView|accessibilityLabel)\(\s*"(?![a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
                RegexRule(
                    description: "bare English placeholder literal",
                    pattern: #"placeholder:\s*"(?![a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
            ],
            allowlistFragments: [
                #"return "OpenAI""#,
                #"return "Azure""#,
            ]
        )

        #expect(violations.isEmpty, violations.joined(separator: "\n"))
    }

    @Test("audited user-visible error files do not return bare English messages")
    func auditedErrorFilesAvoidBareEnglish() throws {
        let violations = try scan(
            files: [
                "App/Extensions/ShareExtension/DOCXExtractor.swift",
                "App/Platform/AI/ShortcutAIService.swift",
                "App/Platform/DeepLink/ReaderLocatorResolver.swift",
                "App/Platform/EventKit/CalendarService.swift",
                "App/Platform/EventKit/RemindersService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Bookshelf/AIOrganizeService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Notes/NotesPDFExportService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/AISettingsSyncService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/IncrementalSyncEngine.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/BackupService.swift",
                "Packages/PTFeatures/Sources/PTFeatures/Sync/WebDAVSyncService.swift",
                "Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkError.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPClient.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPConfiguration.swift",
                "Packages/PTAIServices/Sources/PTAIServices/MCP/MCPTransport.swift",
                "Packages/PTCore/Sources/PTCore/Localization/AppLocalization.swift",
            ],
            rules: [
                RegexRule(
                    description: "bare English error return",
                    pattern: #"(?:return|errorMessage\s*=)\s*"(?![a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+")[A-Za-z][^"]*""#
                ),
            ],
            allowlistFragments: [
                #"return "#808080""#,
                #"return "\(trimmed)/\(remoteFilename)""#,
                #"return "- id=\(id) | "#,
            ]
        )

        #expect(violations.isEmpty, violations.joined(separator: "\n"))
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
