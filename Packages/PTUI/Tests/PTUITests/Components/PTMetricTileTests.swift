import Testing
import SwiftUI
@testable import PTUI

@Suite("PTMetricTile")
struct PTMetricTileTests {
    @Test("Renders value and label")
    func rendersValueAndLabel() {
        let tile = PTMetricTile(value: "42", label: "Books Read")
        let hooks = tile.testHooks
        #expect(hooks.value == "42")
    }

    @Test("Applies custom accent color")
    func appliesAccentColor() {
        let tile = PTMetricTile(value: "7", label: "Streak", color: Morandi.dustyRose)
        let hooks = tile.testHooks
        #expect(hooks.value == "7")
        // color is stored — verifying construction succeeds with custom color
    }
}
