#if canImport(UIKit)
import Foundation
import Testing
@testable import PTReader
import PTCore
import ReadiumShared

@Suite("EPUBAnnotationBridge")
struct EPUBAnnotationBridgeTests {
    @Test("BookNote with highlight type maps to highlight style")
    func noteToDecoratorStyleHighlight() {
        let note = BookNote(
            bookId: 1,
            content: "Important passage",
            cfi: "",
            chapter: "Chapter 1",
            type: "highlight",
            color: "FFF44336",
            updateTime: Date()
        )
        let style = EPUBAnnotationBridge.decoratorStyle(for: note)
        #expect(style.tint == "FFF44336")
        #expect(style.style == "highlight")
    }

    @Test("BookNote with empty color defaults to yellow")
    func noteDefaultColor() {
        let note = BookNote(
            bookId: 1,
            content: "Some text",
            cfi: "",
            chapter: "Chapter 1",
            type: "highlight",
            color: "",
            updateTime: Date()
        )
        let style = EPUBAnnotationBridge.decoratorStyle(for: note)
        #expect(style.tint == HighlightColor.yellow.hex)
    }

    @Test("BookNote with bookmark type maps to underline style")
    func noteToDecoratorStyleBookmark() {
        let note = BookNote(
            bookId: 1,
            content: "Bookmarked text",
            cfi: "",
            chapter: "Chapter 2",
            type: "bookmark",
            color: "FF2196F3",
            updateTime: Date()
        )
        let style = EPUBAnnotationBridge.decoratorStyle(for: note)
        #expect(style.style == "underline")
    }

    @Test("BookNote with note type maps to highlight style")
    func noteToDecoratorStyleNote() {
        let note = BookNote(
            bookId: 1,
            content: "Reader note text",
            cfi: "",
            chapter: "Chapter 3",
            type: "note",
            color: "FF9C27B0",
            updateTime: Date()
        )
        let style = EPUBAnnotationBridge.decoratorStyle(for: note)
        #expect(style.style == "highlight")
    }

    @Test("bookNote factory creates correct BookNote")
    func bookNoteFactory() {
        let href = AnyURL(path: "ch1.xhtml")!
        let locator = Locator(
            href: href,
            mediaType: .xhtml,
            title: "Chapter 1",
            text: Locator.Text(highlight: "selected text")
        )
        let note = EPUBAnnotationBridge.bookNote(
            bookId: 42,
            locator: locator,
            selectedText: "selected text",
            chapter: "Chapter 1",
            color: "FFF44336",
            readerNote: "**Remember** this."
        )
        #expect(note.bookId == 42)
        #expect(note.content == "selected text")
        #expect(note.chapter == "Chapter 1")
        #expect(note.type == "highlight")
        #expect(note.color == "FFF44336")
        #expect(note.readerNote == "**Remember** this.")
        #expect(note.createTime != nil)
        #expect(!note.cfi.isEmpty) // locator serialized to JSON
    }

    @Test("storedString roundtrip preserves locator data")
    func locatorRoundtrip() {
        let href = AnyURL(path: "ch2.xhtml")!
        let locator = Locator(
            href: href,
            mediaType: .xhtml,
            title: "Chapter 2",
            locations: Locator.Locations(progression: 0.5)
        )
        let stored = EPUBAnnotationBridge.storedString(from: locator)
        let recovered = EPUBAnnotationBridge.locator(fromStoredString: stored)
        #expect(recovered != nil)
        #expect(recovered?.title == "Chapter 2")
    }

    @Test("locator from empty string returns nil")
    func emptyLocatorString() {
        let result = EPUBAnnotationBridge.locator(fromStoredString: "")
        #expect(result == nil)
    }
}
#endif
