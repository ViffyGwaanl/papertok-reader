#if os(macOS)
import SwiftUI
import PTCore

/// macOS menu bar commands for PaperTok Reader.
///
/// Keyboard shortcuts:
/// - Cmd+O: Import book
/// - Cmd+\: Toggle AI panel
/// - Cmd+=: Increase font size
/// - Cmd+-: Decrease font size
/// - Left/Right arrow: Previous/next chapter (when reader is active)
///
/// System-provided menus (Edit, Window) are left intact by not replacing
/// their default command groups.
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

        // Format menu — font size
        CommandMenu(String(localized: "macos.menu.format")) {
            Button(String(localized: "macos.menu.increase_font")) {
                NotificationCenter.default.post(name: .increaseFontSize, object: nil)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button(String(localized: "macos.menu.decrease_font")) {
                NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Link(
                "\(String(localized: "app.name")) \(String(localized: "about.website"))",
                destination: URL(string: "https://papertok.ai")!
            )
        }
    }
}
#endif
