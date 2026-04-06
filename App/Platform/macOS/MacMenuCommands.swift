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
            Button("Import Book...") {
                NotificationCenter.default.post(name: .importBook, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        // View menu
        CommandGroup(after: .toolbar) {
            Button("Toggle AI Panel") {
                NotificationCenter.default.post(name: .toggleAIPanel, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()

            Button("Previous Chapter") {
                NotificationCenter.default.post(name: .previousChapter, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Next Chapter") {
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
