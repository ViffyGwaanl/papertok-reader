import Testing
import Foundation
@testable import PTFeatures

@Suite("MarkdownBlockParser")
struct MarkdownBlockParserTests {

    // MARK: - Headings

    @Test("parses H1 through H6 headings")
    func parsesHeadings() {
        let input = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 6)
        for (i, block) in blocks.enumerated() {
            if case .heading(let level, let text) = block {
                #expect(level == i + 1)
                #expect(text == "H\(i + 1)")
            } else {
                Issue.record("Expected heading at index \(i)")
            }
        }
    }

    @Test("heading allows inline formatting")
    func headingWithInlineFormatting() {
        let blocks = MarkdownBlockParser.parse("# **Bold** header")
        #expect(blocks.count == 1)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "**Bold** header")
        } else {
            Issue.record("Expected heading block")
        }
    }

    @Test("line starting with 7+ hashes is not a heading")
    func tooManyHashesFallsBackToParagraph() {
        let blocks = MarkdownBlockParser.parse("####### not a heading")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text == "####### not a heading")
        } else {
            Issue.record("Expected paragraph")
        }
    }

    // MARK: - Paragraphs

    @Test("parses paragraphs separated by blank lines")
    func parsesParagraphs() {
        let input = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let blocks = MarkdownBlockParser.parse(input)
        let paragraphs = blocks.compactMap { block -> String? in
            if case .paragraph(let text) = block { return text }
            return nil
        }
        #expect(paragraphs == ["First paragraph.", "Second paragraph.", "Third paragraph."])
    }

    @Test("joins consecutive non-blank lines into a single paragraph")
    func joinsConsecutiveLines() {
        let blocks = MarkdownBlockParser.parse("line 1\nline 2\nline 3")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text == "line 1\nline 2\nline 3")
        } else {
            Issue.record("Expected paragraph")
        }
    }

    // MARK: - Inline formatting (stays inside paragraphs)

    @Test("bold and italic markers survive inside paragraph text")
    func parsesBoldAndItalic() {
        let blocks = MarkdownBlockParser.parse("This has **bold** and *italic* and __bold__ and _italic_.")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text.contains("**bold**"))
            #expect(text.contains("*italic*"))
            #expect(text.contains("__bold__"))
            #expect(text.contains("_italic_"))
        } else {
            Issue.record("Expected paragraph")
        }
    }

    @Test("strikethrough markers survive inside paragraph text")
    func parsesStrikethrough() {
        let blocks = MarkdownBlockParser.parse("This is ~~deleted~~ text.")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text.contains("~~deleted~~"))
        } else {
            Issue.record("Expected paragraph")
        }
    }

    @Test("inline code markers survive inside paragraph text")
    func parsesInlineCode() {
        let blocks = MarkdownBlockParser.parse("Use `printf` to print.")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text.contains("`printf`"))
        } else {
            Issue.record("Expected paragraph")
        }
    }

    @Test("link markers survive inside paragraph text")
    func parsesLinks() {
        let blocks = MarkdownBlockParser.parse("See [Anthropic](https://www.anthropic.com).")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text.contains("[Anthropic](https://www.anthropic.com)"))
        } else {
            Issue.record("Expected paragraph")
        }
    }

    // MARK: - Code blocks

    @Test("parses fenced code block with language label")
    func parsesCodeBlockWithLanguage() {
        let input = """
        ```swift
        let x = 1
        print(x)
        ```
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .codeBlock(let language, let code) = blocks[0] {
            #expect(language == "swift")
            #expect(code == "let x = 1\nprint(x)")
        } else {
            Issue.record("Expected code block")
        }
    }

    @Test("code block without language label")
    func codeBlockWithoutLanguage() {
        let input = """
        ```
        raw text
        ```
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .codeBlock(let language, let code) = blocks[0] {
            #expect(language == nil || language == "")
            #expect(code == "raw text")
        } else {
            Issue.record("Expected code block")
        }
    }

    // MARK: - Lists

    @Test("parses unordered list with dash and asterisk markers")
    func parsesUnorderedList() {
        let input = """
        - first
        - second
        * third
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .unorderedList(let items) = blocks[0] {
            #expect(items.count == 3)
            #expect(items[0].text == "first")
            #expect(items[1].text == "second")
            #expect(items[2].text == "third")
            #expect(items.allSatisfy { $0.indent == 0 })
        } else {
            Issue.record("Expected unordered list")
        }
    }

    @Test("parses ordered list")
    func parsesOrderedList() {
        let input = """
        1. alpha
        2. beta
        3. gamma
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .orderedList(let items, let startIndex) = blocks[0] {
            #expect(startIndex == 1)
            #expect(items.count == 3)
            #expect(items.map(\.text) == ["alpha", "beta", "gamma"])
        } else {
            Issue.record("Expected ordered list")
        }
    }

    @Test("parses nested unordered list (indentation levels)")
    func parsesNestedList() {
        let input = """
        - top
          - inner
            - deepest
        - second top
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .unorderedList(let items) = blocks[0] {
            #expect(items.count == 4)
            #expect(items[0].indent == 0)
            #expect(items[0].text == "top")
            #expect(items[1].indent == 1)
            #expect(items[1].text == "inner")
            #expect(items[2].indent == 2)
            #expect(items[2].text == "deepest")
            #expect(items[3].indent == 0)
            #expect(items[3].text == "second top")
        } else {
            Issue.record("Expected unordered list")
        }
    }

    // MARK: - Blockquotes

    @Test("parses blockquote")
    func parsesBlockquote() {
        let input = "> quoted line"
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .blockquote(let inner) = blocks[0] {
            #expect(inner.count == 1)
            if case .paragraph(let text) = inner[0] {
                #expect(text == "quoted line")
            } else {
                Issue.record("Expected paragraph inside blockquote")
            }
        } else {
            Issue.record("Expected blockquote")
        }
    }

    @Test("parses nested blockquote via `>>`")
    func parsesNestedBlockquote() {
        let input = """
        > outer
        >> inner
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .blockquote(let outerBlocks) = blocks[0] {
            // Outer should contain a paragraph ("outer") and a nested blockquote
            let hasNested = outerBlocks.contains { block in
                if case .blockquote = block { return true }
                return false
            }
            #expect(hasNested, "Expected nested blockquote inside outer")
        } else {
            Issue.record("Expected blockquote")
        }
    }

    // MARK: - Horizontal rules

    @Test("parses horizontal rule with dashes, asterisks, underscores")
    func parsesHorizontalRule() {
        for marker in ["---", "***", "___"] {
            let blocks = MarkdownBlockParser.parse(marker)
            #expect(blocks.count == 1)
            if case .horizontalRule = blocks[0] {
                // ok
            } else {
                Issue.record("Expected horizontal rule for marker: \(marker)")
            }
        }
    }

    // MARK: - Tables

    @Test("parses simple pipe-syntax table")
    func parsesTable() {
        let input = """
        | a | b |
        | - | - |
        | 1 | 2 |
        | 3 | 4 |
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .table(let headers, let rows) = blocks[0] {
            #expect(headers == ["a", "b"])
            #expect(rows == [["1", "2"], ["3", "4"]])
        } else {
            Issue.record("Expected table")
        }
    }

    @Test("table rows with uneven columns are padded")
    func parsesTableWithUnevenRows() {
        let input = """
        | a | b | c |
        | - | - | - |
        | 1 | 2 |
        | x | y | z |
        """
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 1)
        if case .table(let headers, let rows) = blocks[0] {
            #expect(headers == ["a", "b", "c"])
            #expect(rows.count == 2)
            #expect(rows[0].count == 3)
            #expect(rows[0] == ["1", "2", ""])
            #expect(rows[1] == ["x", "y", "z"])
        } else {
            Issue.record("Expected table")
        }
    }

    // MARK: - Line endings

    @Test("handles CRLF line endings")
    func handlesCRLF() {
        let input = "# Heading\r\n\r\nParagraph.\r\n"
        let blocks = MarkdownBlockParser.parse(input)
        #expect(blocks.count == 2)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Heading")
        } else {
            Issue.record("Expected heading")
        }
        if case .paragraph(let text) = blocks[1] {
            #expect(text == "Paragraph.")
        } else {
            Issue.record("Expected paragraph")
        }
    }

    // MARK: - Fallback

    @Test("plain text without any markers falls back to paragraph")
    func malformedFallsBackToParagraph() {
        let blocks = MarkdownBlockParser.parse("just some text")
        #expect(blocks.count == 1)
        if case .paragraph(let text) = blocks[0] {
            #expect(text == "just some text")
        } else {
            Issue.record("Expected paragraph")
        }
    }

    @Test("empty input yields no blocks")
    func emptyInputNoBlocks() {
        let blocks = MarkdownBlockParser.parse("")
        #expect(blocks.isEmpty)
    }

    @Test("leading and trailing whitespace is trimmed safely")
    func trimsOuterWhitespace() {
        let blocks = MarkdownBlockParser.parse("\n\n  # Hello  \n\n")
        #expect(blocks.count == 1)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Hello")
        } else {
            Issue.record("Expected heading")
        }
    }

    // MARK: - Mixed document

    @Test("parses a mixed document end-to-end")
    func parsesMixedDocument() {
        let input = """
        # Title

        Here is a paragraph with **bold**.

        - item a
        - item b

        ```swift
        let x = 1
        ```

        ---

        > a quote

        | a | b |
        | - | - |
        | 1 | 2 |
        """
        let blocks = MarkdownBlockParser.parse(input)

        let kinds: [String] = blocks.map { block in
            switch block {
            case .heading: return "heading"
            case .paragraph: return "paragraph"
            case .unorderedList: return "ul"
            case .orderedList: return "ol"
            case .codeBlock: return "code"
            case .horizontalRule: return "hr"
            case .blockquote: return "bq"
            case .table: return "table"
            }
        }
        #expect(kinds == ["heading", "paragraph", "ul", "code", "hr", "bq", "table"])
    }
}
