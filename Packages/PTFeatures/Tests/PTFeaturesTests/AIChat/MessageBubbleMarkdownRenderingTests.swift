import Testing
import Foundation
@testable import PTFeatures

@Suite("MessageBubbleMarkdownRendering")
struct MessageBubbleMarkdownRenderingTests {

    // MARK: - inlineAttributed / assistantAttributedBody

    @Test("inline attributed produces non-empty result for plain text")
    func inlineAttributedForPlainText() {
        let attr = MessageBubbleView.assistantAttributedBody(for: "Hello world")
        let plain = String(attr.characters)
        #expect(plain == "Hello world")
    }

    @Test("inline attributed handles citation markers")
    func inlineAttributedHandlesCitations() {
        let attr = MessageBubbleView.assistantAttributedBody(for: "See [1] now.")
        var raised = 0
        for run in attr.runs where (run.baselineOffset ?? 0) > 0 {
            raised += 1
        }
        #expect(raised >= 1)
    }

    @Test("inline attributed preserves bold from markdown")
    func inlineAttributedPreservesBold() {
        let attr = MessageBubbleView.assistantAttributedBody(for: "This is **bold** text.")
        // Once AttributedString parses markdown, the literal `**` is removed.
        let plain = String(attr.characters)
        #expect(plain.contains("bold"))
        #expect(!plain.contains("**"))
    }

    // MARK: - Parser -> renderer wiring sanity

    @Test("parser yields a heading block that downstream renderer handles")
    func parserEmitsHeading() {
        let blocks = MarkdownBlockParser.parse("# Title\n\nBody text.")
        guard blocks.count >= 2 else {
            Issue.record("Expected at least heading + paragraph")
            return
        }
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Title")
        } else {
            Issue.record("First block should be heading")
        }
        if case .paragraph(let text) = blocks[1] {
            #expect(text == "Body text.")
        } else {
            Issue.record("Second block should be paragraph")
        }
    }

    @Test("parser yields a code block that downstream renderer handles")
    func parserEmitsCodeBlock() {
        let input = """
        ```swift
        let x = 1
        ```
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .codeBlock(let language, let code) = blocks[0] {
            #expect(language == "swift")
            #expect(code == "let x = 1")
        } else {
            Issue.record("Expected code block")
        }
    }

    @Test("parser yields a blockquote that downstream renderer handles")
    func parserEmitsBlockquote() {
        let blocks = MarkdownBlockParser.parse("> quoted")
        #expect(blocks.count == 1)
        if case .blockquote = blocks[0] {
            // ok
        } else {
            Issue.record("Expected blockquote")
        }
    }

    @Test("parser yields a table that downstream renderer handles")
    func parserEmitsTable() {
        let input = """
        | a | b |
        | - | - |
        | 1 | 2 |
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .table(let headers, let rows) = blocks[0] {
            #expect(headers == ["a", "b"])
            #expect(rows == [["1", "2"]])
        } else {
            Issue.record("Expected table")
        }
    }

    @Test("parser yields horizontal rule that downstream renderer handles")
    func parserEmitsHorizontalRule() {
        let blocks = MarkdownBlockParser.parse("---")
        #expect(blocks.count == 1)
        if case .horizontalRule = blocks[0] {
            // ok
        } else {
            Issue.record("Expected horizontal rule")
        }
    }
}
