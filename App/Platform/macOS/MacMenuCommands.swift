#if os(macOS)
import SwiftUI

/// macOS menu bar commands for PaperTok Reader.
///
/// Keyboard shortcuts:
/// - Cmd+O: Import book
/// - Cmd+\: Toggle AI panel
/// - Left/Right arrow: Previous/next chapter (when reader is active)
public struct MacMenuCommands: Commands {
    public init() {}

    public var body: some Commands {
        // File menu
        CommandGroup(after: .newItem) {
            Button(String(localized: "bookshelf.import_book")) {
                NotificationCenter.default.post(name: .importBook, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        // View menu
        CommandGroup(after: .toolbar) {
            Button(String(localized: "reader.toggle_ai_panel")) {
                NotificationCenter.default.post(name: .toggleAIPanel, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()

            Button(String(localized: "reader.previous_chapter")) {
                NotificationCenter.default.post(name: .previousChapter, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(String(localized: "reader.next_chapter")) {
                NotificationCenter.default.post(name: .nextChapter, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Link("PaperTok Website", destination: URL(string: "https://papertok.ai")!)
        }
    }
}

// MARK: - Notification Names for macOS Commands

extension Notification.Name {
    static let importBook = Notification.Name("PaperTokImportBook")
    static let toggleAIPanel = Notification.Name("PaperTokToggleAI")
    static let previousChapter = Notification.Name("PaperTokPreviousChapter")
    static let nextChapter = Notification.Name("PaperTokNextChapter")
}
#endif
