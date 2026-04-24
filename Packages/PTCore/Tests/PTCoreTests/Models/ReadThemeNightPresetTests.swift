import Testing
import Foundation
@testable import PTCore

@Suite("ReadTheme Night preset")
struct ReadThemeNightPresetTests {
    @Test("Night preset exists as a distinct static member")
    func nightPresetExists() {
        let night = ReadTheme.defaultNight
        // Distinct from other presets
        #expect(night != .defaultLight)
        #expect(night != .defaultDark)
        #expect(night != .defaultSepia)
    }

    @Test("Night preset has pure #000000 background")
    func nightPresetHasBlackBackground() {
        let night = ReadTheme.defaultNight
        // Hex is AARRGGBB. Pure black = FF000000.
        #expect(night.backgroundColor == "FF000000")
    }

    @Test("Night preset text is dimmed (not pure white) for OLED reading comfort")
    func nightPresetTextIsDimmed() {
        let night = ReadTheme.defaultNight
        // Luminance should be in the muted-grey range so the contrast is not
        // harsh against pure black. Parse RGB components and assert.
        let hex = night.textColor
        #expect(hex.count == 8, "textColor must be AARRGGBB")
        let rgb = String(hex.dropFirst(2))
        guard rgb.count == 6,
              let rValue = UInt32(rgb.prefix(2), radix: 16),
              let gValue = UInt32(rgb.dropFirst(2).prefix(2), radix: 16),
              let bValue = UInt32(rgb.dropFirst(4), radix: 16) else {
            Issue.record("textColor not parseable: \(hex)")
            return
        }
        let red = Double(rValue) / 255.0
        let green = Double(gValue) / 255.0
        let blue = Double(bValue) / 255.0
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        // Target "dimmed" — between 0.4 and 0.8 (roughly 0.6 ± tolerance).
        #expect(luminance > 0.4)
        #expect(luminance < 0.8)
    }
}
