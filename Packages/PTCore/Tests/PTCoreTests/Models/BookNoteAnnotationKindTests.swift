import Foundation
import Testing
@testable import PTCore

@Suite("BookNoteAnnotationKind")
struct BookNoteAnnotationKindTests {

    @Test("Enum covers highlight, underline, strikethrough")
    func allCases() {
        #expect(BookNoteAnnotationKind.allCases.count == 3)
        #expect(BookNoteAnnotationKind.allCases.contains(.highlight))
        #expect(BookNoteAnnotationKind.allCases.contains(.underline))
        #expect(BookNoteAnnotationKind.allCases.contains(.strikethrough))
    }

    @Test("Raw values match the type column strings")
    func rawValues() {
        #expect(BookNoteAnnotationKind.highlight.rawValue == "highlight")
        #expect(BookNoteAnnotationKind.underline.rawValue == "underline")
        #expect(BookNoteAnnotationKind.strikethrough.rawValue == "strikethrough")
    }

    @Test("BookNote.annotationKind round-trips through the type column")
    func roundTripAccessor() {
        var note = BookNote(type: "highlight")
        #expect(note.annotationKind == .highlight)

        note.annotationKind = .underline
        #expect(note.type == "underline")
        #expect(note.annotationKind == .underline)

        note.annotationKind = .strikethrough
        #expect(note.type == "strikethrough")
        #expect(note.annotationKind == .strikethrough)

        note.annotationKind = .highlight
        #expect(note.type == "highlight")
    }

    @Test("Unknown raw values fall back to highlight")
    func fallbackOnUnknownType() {
        let note = BookNote(type: "bookmark")
        #expect(note.annotationKind == .highlight)

        let noteNote = BookNote(type: "note")
        #expect(noteNote.annotationKind == .highlight)

        let garbage = BookNote(type: "zzz")
        #expect(garbage.annotationKind == .highlight)
    }

    @Test("All three kinds are distinct")
    func distinctness() {
        let set: Set<BookNoteAnnotationKind> = [.highlight, .underline, .strikethrough]
        #expect(set.count == 3)
    }
}
