import Foundation

/// Block-level element produced by `MarkdownBlockParser`.
///
/// Inline formatting (bold, italic, strikethrough, inline code, links,
/// citation markers) is handled by `AttributedString(markdown:)` inside each
/// block's renderer. This parser is concerned only with block-level structure.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList(items: [MarkdownListItem])
    case orderedList(items: [MarkdownListItem], startIndex: Int)
    case blockquote(blocks: [MarkdownBlock])
    case codeBlock(language: String?, code: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
}

/// Single item in a markdown list. Indentation levels are zero-based and
/// preserved so callers can render nested lists.
public struct MarkdownListItem: Equatable, Sendable {
    public let indent: Int
    public let text: String

    public init(indent: Int, text: String) {
        self.indent = indent
        self.text = text
    }
}

/// Pure-Swift markdown block parser. Splits raw text into an ordered sequence
/// of `MarkdownBlock` values. Inline formatting is intentionally left untouched
/// so that downstream renderers can feed each paragraph/heading through
/// `AttributedString(markdown:)` + the citation marker overlay.
///
/// Supported block types:
/// - ATX headings (`#` .. `######`)
/// - Fenced code blocks (``` ``` `` `` ```)
/// - Unordered lists (`-`, `*`) with nested indentation
/// - Ordered lists (`1.`, `2.`) with nested indentation
/// - Blockquotes (`>`, `>>`) — recursive
/// - Horizontal rules (`---`, `***`, `___`)
/// - Pipe tables with header separator row
/// - Paragraphs (fallback for anything else)
public enum MarkdownBlockParser {

    /// Parses the provided markdown source into a sequence of block elements.
    /// Returns an empty array for empty / whitespace-only input.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        // Normalize line endings up-front.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        return parseLines(Array(lines))
    }

    // MARK: - Line-level parsing

    private static func parseLines(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines between blocks.
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Horizontal rule.
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // ATX heading.
            if let heading = matchHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Table (needs a separator row on the following line).
            if isTableLine(trimmed), i + 1 < lines.count,
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let (block, consumed) = parseTable(startingAt: i, lines: lines)
                blocks.append(block)
                i += consumed
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                let (block, consumed) = parseBlockquote(startingAt: i, lines: lines)
                blocks.append(block)
                i += consumed
                continue
            }

            // Unordered list.
            if isUnorderedBullet(line) {
                let (block, consumed) = parseUnorderedList(startingAt: i, lines: lines)
                blocks.append(block)
                i += consumed
                continue
            }

            // Ordered list.
            if isOrderedBullet(line) {
                let (block, consumed) = parseOrderedList(startingAt: i, lines: lines)
                blocks.append(block)
                i += consumed
                continue
            }

            // Paragraph (consume consecutive non-blank, non-block-starting lines).
            let (paragraphBlock, consumed) = parseParagraph(startingAt: i, lines: lines)
            blocks.append(paragraphBlock)
            i += consumed
        }
        return blocks
    }

    // MARK: - Headings

    private static func matchHeading(_ line: String) -> MarkdownBlock? {
        var level = 0
        for ch in line {
            if ch == "#" {
                level += 1
            } else {
                break
            }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        // ATX requires a space after the hash run (or an empty heading body).
        guard rest.first == " " || rest.isEmpty else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    // MARK: - Horizontal rule

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        guard let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    // MARK: - Paragraphs

    private static func parseParagraph(startingAt start: Int, lines: [String]) -> (MarkdownBlock, Int) {
        var collected: [String] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if trimmed.hasPrefix("```") { break }
            if isHorizontalRule(trimmed) { break }
            if matchHeading(trimmed) != nil { break }
            if trimmed.hasPrefix(">") { break }
            if isUnorderedBullet(line) { break }
            if isOrderedBullet(line) { break }
            if isTableLine(trimmed), i + 1 < lines.count,
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) { break }
            collected.append(trimmed)
            i += 1
        }
        let text = collected.joined(separator: "\n")
        return (.paragraph(text), max(i - start, 1))
    }

    // MARK: - Blockquotes

    private static func parseBlockquote(startingAt start: Int, lines: [String]) -> (MarkdownBlock, Int) {
        var collected: [String] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            // Strip exactly one leading `>` plus at most one following space.
            var stripped = String(trimmed.dropFirst(1))
            if stripped.hasPrefix(" ") { stripped.removeFirst() }
            collected.append(stripped)
            i += 1
        }
        let innerBlocks = parseLines(collected)
        return (.blockquote(blocks: innerBlocks), i - start)
    }

    // MARK: - Lists

    private static let unorderedBulletPattern =
        try! NSRegularExpression(pattern: "^( *)([-*])\\s+(.+)$")
    private static let orderedBulletPattern =
        try! NSRegularExpression(pattern: "^( *)(\\d+)\\.\\s+(.+)$")

    private static func isUnorderedBullet(_ line: String) -> Bool {
        return match(line: line, regex: unorderedBulletPattern) != nil
    }

    private static func isOrderedBullet(_ line: String) -> Bool {
        return match(line: line, regex: orderedBulletPattern) != nil
    }

    private static func parseUnorderedList(startingAt start: Int, lines: [String]) -> (MarkdownBlock, Int) {
        var items: [MarkdownListItem] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let m = match(line: line, regex: unorderedBulletPattern) else { break }
            let leading = m.groups[0]
            let content = m.groups[2]
            let indent = indentLevel(from: leading)
            items.append(MarkdownListItem(indent: indent, text: content))
            i += 1
        }
        return (.unorderedList(items: items), max(i - start, 1))
    }

    private static func parseOrderedList(startingAt start: Int, lines: [String]) -> (MarkdownBlock, Int) {
        var items: [MarkdownListItem] = []
        var i = start
        var startIndex = 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let m = match(line: line, regex: orderedBulletPattern) else { break }
            let leading = m.groups[0]
            let number = m.groups[1]
            let content = m.groups[2]
            let indent = indentLevel(from: leading)
            if items.isEmpty, let parsedStart = Int(number) {
                startIndex = parsedStart
            }
            items.append(MarkdownListItem(indent: indent, text: content))
            i += 1
        }
        return (.orderedList(items: items, startIndex: startIndex), max(i - start, 1))
    }

    /// Maps leading spaces to an indent level (2 spaces per level by default,
    /// but any non-zero leading whitespace is clamped to at least level 1).
    private static func indentLevel(from leading: String) -> Int {
        let count = leading.count
        if count == 0 { return 0 }
        return max(1, count / 2)
    }

    // MARK: - Tables

    private static func isTableLine(_ line: String) -> Bool {
        // Must contain at least one pipe and not be empty/HR.
        guard line.contains("|") else { return false }
        return true
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        // Accept `| - | :--- | ---: |` style separators.
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !core.isEmpty else { return false }
            return core.allSatisfy { $0 == "-" }
        }
    }

    private static func splitTableCells(_ line: String) -> [String] {
        var content = line
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTable(startingAt start: Int, lines: [String]) -> (MarkdownBlock, Int) {
        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        let headers = splitTableCells(headerLine)
        var rows: [[String]] = []
        var i = start + 2 // skip header + separator
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard isTableLine(trimmed) else { break }
            var cells = splitTableCells(trimmed)
            while cells.count < headers.count { cells.append("") }
            if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
            rows.append(cells)
            i += 1
        }
        return (.table(headers: headers, rows: rows), i - start)
    }

    // MARK: - Regex helpers

    private struct RegexMatch {
        let full: String
        let groups: [String]
    }

    private static func match(line: String, regex: NSRegularExpression) -> RegexMatch? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound {
                groups.append("")
            } else {
                groups.append(ns.substring(with: r))
            }
        }
        return RegexMatch(full: ns.substring(with: m.range), groups: groups)
    }
}
