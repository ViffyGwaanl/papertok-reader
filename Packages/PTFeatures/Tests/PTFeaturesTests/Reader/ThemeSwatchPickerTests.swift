import Foundation
import Testing
@testable import PTFeatures
import PTCore

@Suite("ThemeSwatchPicker")
struct ThemeSwatchPickerTests {
    @Test("Renders four presets: light, sepia, dark, night")
    func rendersFourPresets() {
        let presets = ThemeSwatchPreset.allPresets
        #expect(presets.count == 4)
        #expect(presets[0].theme == ReadTheme.defaultLight)
        #expect(presets[1].theme == ReadTheme.defaultSepia)
        #expect(presets[2].theme == ReadTheme.defaultDark)
        #expect(presets[3].theme == ReadTheme.defaultNight)
    }

    @Test("Active preset is resolved from the current reading theme")
    func activeThemeIsIdentifiable() {
        #expect(ThemeSwatchPreset.active(for: .defaultLight)?.kind == .light)
        #expect(ThemeSwatchPreset.active(for: .defaultSepia)?.kind == .sepia)
        #expect(ThemeSwatchPreset.active(for: .defaultDark)?.kind == .dark)
        #expect(ThemeSwatchPreset.active(for: .defaultNight)?.kind == .night)
    }

    @Test("Unknown / custom themes resolve to nil active preset (no border shown)")
    func unknownThemeHasNoActive() {
        var custom = ReadTheme.defaultLight
        custom.backgroundColor = "FF112233"
        custom.textColor = "FFFFFFFF"
        #expect(ThemeSwatchPreset.active(for: custom) == nil)
    }

    @Test("Night swatch preset carries the pure black background")
    func nightSwatchIsPureBlack() {
        let night = ThemeSwatchPreset.allPresets.first { $0.kind == .night }
        #expect(night != nil)
        #expect(night?.theme.backgroundColor == "FF000000")
    }
}
