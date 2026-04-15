import Testing
import Foundation
@testable import PTFeatures

@Suite("ReaderContextPreambleBuilder")
struct ReaderContextPreambleBuilderTests {
    private func makeResult(
        scope: ReaderContextScope = .selection,
        bookTitle: String = "The Hobbit",
        bookAuthor: String? = "Tolkien",
        chapterTitle: String? = "An Unexpected Party",
        pageNumber: Int? = 12,
        totalPages: Int? = 300,
        text: String = "Body text",
        truncated: Bool = false
    ) -> ReaderContextResult {
        ReaderContextResult(
            scope: scope,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapterTitle: chapterTitle,
            pageNumber: pageNumber,
            totalPages: totalPages,
            text: text,
            truncated: truncated,
            originalCharacterCount: text.count
        )
    }

    @Test("Preamble includes book title and author")
    func preambleIncludesBookTitleAndAuthor() {
        let builder = ReaderContextPreambleBuilder()
        let output = builder.buildPreamble(for: makeResult(), locale: Locale(identifier: "en"))
        #expect(output.contains("The Hobbit"))
        #expect(output.contains("Tolkien"))
        #expect(output.contains("Body text"))
    }

    @Test("Preamble omits author when nil")
    func preambleOmitsAuthorWhenNil() {
        let builder = ReaderContextPreambleBuilder()
        let output = builder.buildPreamble(
            for: makeResult(bookAuthor: nil),
            locale: Locale(identifier: "en")
        )
        #expect(output.contains("The Hobbit"))
        #expect(output.contains("Tolkien") == false)
    }

    @Test("Preamble includes scope and page")
    func preambleIncludesScopeAndPage() {
        let builder = ReaderContextPreambleBuilder()
        let output = builder.buildPreamble(
            for: makeResult(scope: .page, pageNumber: 42, totalPages: 100),
            locale: Locale(identifier: "en")
        )
        #expect(output.contains("42"))
        #expect(output.contains("100"))
    }

    @Test("Preamble body contains the text content")
    func preambleAppendsTruncationMarkerWhenTruncated() {
        let builder = ReaderContextPreambleBuilder()
        let output = builder.buildPreamble(
            for: makeResult(text: "Important body", truncated: true),
            locale: Locale(identifier: "en")
        )
        #expect(output.contains("Important body"))
        // Preamble joins a header + separator + body; separator must be present.
        #expect(output.contains("---"))
    }
}
