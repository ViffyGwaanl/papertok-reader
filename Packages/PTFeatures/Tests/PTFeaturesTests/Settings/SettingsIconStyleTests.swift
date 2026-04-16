import Testing
import SwiftUI
@testable import PTFeatures

/// Smoke tests guarding the Claude-style monochrome rendering of settings
/// row icons. These assertions prevent accidental regressions back to the
/// iOS Settings-app tinted rounded-square aesthetic.
@Suite("SettingsIconStyle — Claude monochrome polish")
struct SettingsIconStyleTests {
    @Test("SettingsIconLabel reports monochrome icon style")
    func settingsIconLabelIsMonochrome() {
        let label = SettingsIconLabel(
            "Providers",
            systemImage: "sparkles",
            subtitle: "OpenAI"
        )
        #expect(label.testHooks.iconStyle == .monochrome)
        #expect(label.testHooks.systemImage == "sparkles")
        #expect(label.testHooks.hasSubtitle == true)
    }

    @Test("SettingsIconLabel ignores tint arguments for visual style")
    func tintArgumentDoesNotAffectMonochromeStyle() {
        // Legacy call sites still pass a tint for API compatibility.
        // Regardless of the tint, the rendered style must stay monochrome.
        let label = SettingsIconLabel(
            "Memory",
            systemImage: "brain.head.profile",
            tint: .blue
        )
        #expect(label.testHooks.iconStyle == .monochrome)
    }

    @Test("SettingsIconLabel with nil subtitle reports no subtitle")
    func nilSubtitleReportsFalse() {
        let label = SettingsIconLabel(
            "Storage",
            systemImage: "internaldrive.fill"
        )
        #expect(label.testHooks.hasSubtitle == false)
    }

    @Test("SettingsIconLabel treats empty subtitle as absent")
    func emptySubtitleReportsFalse() {
        let label = SettingsIconLabel(
            "Storage",
            systemImage: "internaldrive.fill",
            subtitle: ""
        )
        #expect(label.testHooks.hasSubtitle == false)
    }
}
