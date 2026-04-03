import Testing
import SwiftUI
@testable import PTUI

@Suite("MorandiPalette")
struct MorandiPaletteTests {
    @Test("Primary colors are defined")
    func primaryColors() {
        #expect(Morandi.sage != Color.clear)
        #expect(Morandi.dustyRose != Color.clear)
        #expect(Morandi.warmGray != Color.clear)
        #expect(Morandi.stone != Color.clear)
        #expect(Morandi.clay != Color.clear)
    }

    @Test("Semantic colors are defined")
    func semanticColors() {
        #expect(Morandi.primaryText != Color.clear)
        #expect(Morandi.secondaryText != Color.clear)
        #expect(Morandi.background != Color.clear)
        #expect(Morandi.cardBackground != Color.clear)
        #expect(Morandi.accent != Color.clear)
    }

    @Test("Accent presets has at least 6 options")
    func accentPresets() {
        #expect(Morandi.accentPresets.count >= 6)
    }

    @Test("Highlight colors map to 5 annotation colors")
    func highlightColors() {
        #expect(Morandi.highlightYellow != Color.clear)
        #expect(Morandi.highlightRed != Color.clear)
        #expect(Morandi.highlightBlue != Color.clear)
        #expect(Morandi.highlightGreen != Color.clear)
        #expect(Morandi.highlightPurple != Color.clear)
    }
}
