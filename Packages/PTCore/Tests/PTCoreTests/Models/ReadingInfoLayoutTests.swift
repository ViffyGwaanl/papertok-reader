import Testing
import Foundation
@testable import PTCore

/// W6.3b — Reader header/footer display (reading info).
@Suite("ReadingInfoLayout")
struct ReadingInfoLayoutTests {
    @Test("Default layout has chapter title, page number, and progress")
    func defaultLayoutHasChapterPageProgress() {
        let layout = ReadingInfoLayout.default
        #expect(layout.topLeft == .nothing)
        #expect(layout.topCenter == .chapterTitle)
        #expect(layout.topRight == .nothing)
        #expect(layout.bottomLeft == .pageNumber)
        #expect(layout.bottomCenter == .nothing)
        #expect(layout.bottomRight == .progressPercentage)
    }

    @Test("Codable round-trip preserves all 6 slots")
    func codableRoundTrip() throws {
        var layout = ReadingInfoLayout.default
        layout.topLeft = .batteryLevel
        layout.topCenter = .clock
        layout.topRight = .readingTime
        layout.bottomLeft = .pageNumber
        layout.bottomCenter = .chapterTitle
        layout.bottomRight = .progressPercentage

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(ReadingInfoLayout.self, from: data)
        #expect(decoded == layout)
    }

    @Test("Legacy BookStyle JSON without reading_info decodes with default layout")
    func backwardCompatDecodesWithoutReadingInfoField() throws {
        // Pre-W6.3b BookStyle JSON — no reading_info field.
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
            "bottom_margin": 50.0,
            "max_column_count": "auto",
            "column_threshold": 800,
            "writing_mode": "auto"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BookStyle.self, from: legacyJSON)
        #expect(decoded.readingInfo == .default)
        #expect(decoded.readingInfo.topCenter == .chapterTitle)
        #expect(decoded.readingInfo.bottomLeft == .pageNumber)
        #expect(decoded.readingInfo.bottomRight == .progressPercentage)
    }

    @Test("ReadingInfoField has all 7 cases")
    func enumHasSevenFields() {
        #expect(ReadingInfoField.allCases.count == 7)
        let raws = Set(ReadingInfoField.allCases.map(\.rawValue))
        #expect(raws == [
            "nothing",
            "chapter_title",
            "page_number",
            "progress_percentage",
            "reading_time",
            "battery_level",
            "clock",
        ])
    }

    @Test("BookStyle default carries ReadingInfoLayout.default")
    func bookStyleDefaultIncludesReadingInfo() {
        let style = BookStyle.default
        #expect(style.readingInfo == .default)
    }

    @Test("BookStyle JSON round-trip preserves custom reading info")
    func bookStyleRoundTripPreservesReadingInfo() throws {
        var style = BookStyle.default
        style.readingInfo = ReadingInfoLayout(
            topLeft: .clock,
            topCenter: .chapterTitle,
            topRight: .batteryLevel,
            bottomLeft: .pageNumber,
            bottomCenter: .readingTime,
            bottomRight: .progressPercentage
        )

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
        #expect(decoded.readingInfo == style.readingInfo)
    }
}
