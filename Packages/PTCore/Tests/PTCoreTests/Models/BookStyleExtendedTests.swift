import Testing
import Foundation
@testable import PTCore

/// W6.3a — Extended BookStyle fields (column count, writing mode, etc.)
@Suite("BookStyleExtended")
struct BookStyleExtendedTests {
    @Test("New fields have backward-compat defaults")
    func newFieldsHaveBackwardCompatDefaults() {
        let style = BookStyle.default
        #expect(style.maxColumnCount == .auto)
        #expect(style.columnThreshold == 800)
        #expect(style.writingMode == .auto)
    }

    @Test("ColumnCount enum round-trips through JSON")
    func columnCountEnumRoundTrip() throws {
        let all: [BookStyle.ColumnCount] = [.auto, .single, .double]
        for value in all {
            var style = BookStyle.default
            style.maxColumnCount = value
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
            #expect(decoded.maxColumnCount == value)
        }
    }

    @Test("WritingMode enum round-trips through JSON")
    func writingModeEnumRoundTrip() throws {
        let all: [BookStyle.WritingMode] = [.auto, .horizontalTb, .verticalRl]
        for value in all {
            var style = BookStyle.default
            style.writingMode = value
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
            #expect(decoded.writingMode == value)
        }
    }

    @Test("Legacy JSON without new fields decodes with defaults")
    func legacyJSONWithoutNewFieldsDecodes() throws {
        // Pre-W6.3a JSON shape — no max_column_count / column_threshold / writing_mode
        let legacyJSON = """
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

        let decoded = try JSONDecoder().decode(BookStyle.self, from: legacyJSON)

        #expect(decoded.fontSize == 1.4)
        #expect(decoded.fontFamily == "Arial")
        #expect(decoded.maxColumnCount == .auto)
        #expect(decoded.columnThreshold == 800)
        #expect(decoded.writingMode == .auto)
    }

    @Test("Round-trip preserves all new fields")
    func roundTripPreservesAllNewFields() throws {
        var style = BookStyle.default
        style.maxColumnCount = .double
        style.columnThreshold = 1000
        style.writingMode = .verticalRl
        style.wordSpacing = 0.35
        style.paragraphSpacing = 1.75
        style.topMargin = 42
        style.bottomMargin = 33

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BookStyle.self, from: data)

        #expect(decoded.maxColumnCount == .double)
        #expect(decoded.columnThreshold == 1000)
        #expect(decoded.writingMode == .verticalRl)
        #expect(decoded.wordSpacing == 0.35)
        #expect(decoded.paragraphSpacing == 1.75)
        #expect(decoded.topMargin == 42)
        #expect(decoded.bottomMargin == 33)
    }

    @Test("ColumnCount has expected cases")
    func columnCountCases() {
        #expect(BookStyle.ColumnCount.allCases.count == 3)
        #expect(BookStyle.ColumnCount(rawValue: "auto") == .auto)
        #expect(BookStyle.ColumnCount(rawValue: "single") == .single)
        #expect(BookStyle.ColumnCount(rawValue: "double") == .double)
    }

    @Test("WritingMode has expected cases")
    func writingModeCases() {
        #expect(BookStyle.WritingMode.allCases.count == 3)
        #expect(BookStyle.WritingMode(rawValue: "auto") == .auto)
        #expect(BookStyle.WritingMode(rawValue: "horizontalTb") == .horizontalTb)
        #expect(BookStyle.WritingMode(rawValue: "verticalRl") == .verticalRl)
    }
}
