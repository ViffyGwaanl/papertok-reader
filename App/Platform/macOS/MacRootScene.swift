#if os(macOS)
import SwiftUI

struct MacRootScene<Content: View>: Scene {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some Scene {
        WindowGroup {
            content
        }
        .commands {
            MacMenuCommands()
        }
        .defaultSize(width: 1100, height: 750)
    }
}
#endif
