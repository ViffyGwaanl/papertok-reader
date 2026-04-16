import Testing
import SwiftUI
@testable import PTUI

@Suite("PTSettingsCard")
struct PTSettingsCardTests {
    @Test("Renders icon, title, subtitle, and trailing")
    func rendersAllParts() {
        let card = PTSettingsCard(
            icon: "gear",
            title: "Title",
            subtitle: "Subtitle"
        ) {
            Toggle("", isOn: .constant(true))
        }
        let hooks = card.testHooks
        #expect(hooks.icon == "gear")
        #expect(hooks.hasSubtitle == true)
    }

    @Test("Hides subtitle when nil")
    func hidesSubtitleWhenNil() {
        let card = PTSettingsCard(
            icon: "star",
            title: "Title"
        ) {
            EmptyView()
        }
        let hooks = card.testHooks
        #expect(hooks.hasSubtitle == false)
    }

    @Test("Icon color defaults to neutral primary text for monochrome Claude-style rendering")
    func iconColorDefaultsToPrimaryText() {
        let card = PTSettingsCard(icon: "bell", title: "Notifications") { EmptyView() }
        // Default iconColor should be Morandi.primaryText (monochrome neutral),
        // matching the Claude app aesthetic where row icons are not tinted.
        #expect(card.testHooks.icon == "bell")
        #expect(card.testHooks.iconColor == Morandi.primaryText)
    }
}
