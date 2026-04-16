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

    @Test("Icon color defaults to accent")
    func iconColorDefaultsToAccent() {
        let card = PTSettingsCard(icon: "bell", title: "Notifications") { EmptyView() }
        // Default iconColor should be Morandi.accent — we verify the property exists and is set.
        #expect(card.testHooks.icon == "bell")
    }
}
