import Testing
import Foundation
@testable import PTCore

/// W7.1 — Reader immersion preference: `autoHideChromeSeconds`.
@Suite("BookStyleAutoHide")
struct BookStyleAutoHideTests {
    @Test("autoHideChromeSeconds defaults to 3")
    func autoHideChromeSecondsDefaultsTo3() {
        let style = BookStyle.default
        #expect(style.autoHideChromeSeconds == 3.0)
    }

    @Test("autoHideChromeSeconds round-trips through Codable")
    func roundTripsThroughCodable() throws {
        var style = BookStyle.default
        style.autoHideChromeSeconds = 7.5
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
        #expect(decoded.autoHideChromeSeconds == 7.5)
    }

    @Test("Missing autoHideChromeSeconds decodes as 3 (backward-compat)")
    func backwardCompatWithoutField() throws {
        // Simulate a payload written before W7.1 — the field must be absent.
        let json = """
        {
          "font_size": 1.4,
          "font_family": "Arial",
          "line_height": 1.8,
          "letter_spacing": 0.0,
          "word_spacing": 0.0,
          "paragraph_spacing": 1.0,
          "side_margin": 6.0,
          "top_margin": 90.0,
          "bottom_margin": 50.0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BookStyle.self, from: json)
        #expect(decoded.autoHideChromeSeconds == 3.0)
    }

    @Test("Zero disables auto-hide (opt-out)")
    func zeroMeansNeverHide() {
        var style = BookStyle.default
        style.autoHideChromeSeconds = 0
        #expect(style.autoHideChromeSeconds == 0)
    }
}
