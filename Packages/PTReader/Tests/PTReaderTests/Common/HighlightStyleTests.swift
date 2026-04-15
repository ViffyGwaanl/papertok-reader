import Testing
import Foundation
@testable import PTReader

@Suite("HighlightStyle")
struct HighlightStyleTests {
    @Test("All five colors are defined")
    func allColors() {
        let colors = HighlightColor.allCases
        #expect(colors.count == 5)
        #expect(colors.contains(.yellow))
        #expect(colors.contains(.red))
        #expect(colors.contains(.blue))
        #expect(colors.contains(.green))
        #expect(colors.contains(.purple))
    }

    @Test("Hex values are correct")
    func hexValues() {
        #expect(HighlightColor.yellow.hex == "FFFFEB3B")
        #expect(HighlightColor.red.hex == "FFF44336")
        #expect(HighlightColor.blue.hex == "FF2196F3")
        #expect(HighlightColor.green.hex == "FF4CAF50")
        #expect(HighlightColor.purple.hex == "FF9C27B0")
    }

    @Test("Initializes from database color string")
    func fromDatabaseString() {
        #expect(HighlightColor(databaseValue: "FFFFEB3B") == .yellow)
        #expect(HighlightColor(databaseValue: "FFF44336") == .red)
        #expect(HighlightColor(databaseValue: "unknown") == .yellow)
    }

    @Test("NoteType enum covers all types")
    func noteTypes() {
        #expect(NoteType.allCases.count == 5)
        #expect(NoteType(rawValue: "highlight") == .highlight)
        #expect(NoteType(rawValue: "bookmark") == .bookmark)
        #expect(NoteType(rawValue: "note") == .note)
        #expect(NoteType(rawValue: "underline") == .underline)
        #expect(NoteType(rawValue: "strikethrough") == .strikethrough)
    }

    @Test("ContentSearchResult stores fields correctly")
    func searchResult() {
        let result = ContentSearchResult(
            text: "matched text",
            chapterTitle: "Chapter 1",
            chapterHref: "/chapter1.xhtml",
            textBefore: "before ",
            textAfter: " after",
            progression: 0.25
        )
        #expect(result.text == "matched text")
        #expect(result.chapterTitle == "Chapter 1")
        #expect(result.progression == 0.25)
    }
}
