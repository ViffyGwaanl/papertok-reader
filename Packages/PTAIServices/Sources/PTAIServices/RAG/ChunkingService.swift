import Foundation

/// Represents one chunk of text produced by `ChunkingService`.
public struct TextChunk: Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let startOffset: Int
    public let endOffset: Int
    public let chunkIndex: Int
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        text: String,
        startOffset: Int,
        endOffset: Int,
        chunkIndex: Int,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.chunkIndex = chunkIndex
        self.metadata = metadata
    }
}

/// Splits text into overlapping chunks suitable for embedding.
///
/// Targets ~512 tokens (~2000 chars) with 64 token (~256 char) overlap.
/// Prefers paragraph boundaries, then sentence boundaries, then a raw character
/// fallback when a single paragraph is larger than `chunkSize`.
public struct ChunkingService: Sendable {
    public let chunkSize: Int
    public let overlap: Int

    public init(chunkSize: Int = 2000, overlap: Int = 256) {
        precondition(chunkSize > 0, "chunkSize must be > 0")
        precondition(overlap >= 0 && overlap < chunkSize, "overlap must be in [0, chunkSize)")
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    public func chunk(text: String, metadata: [String: String] = [:]) -> [TextChunk] {
        let trimmed = text
        guard !trimmed.isEmpty else { return [] }

        // Tokenise the source into (segment, startOffset) pairs using paragraph splits,
        // falling back to sentence splits, then fixed-size character windows for
        // oversized segments.
        let segments = splitSegments(text: trimmed)

        var chunks: [TextChunk] = []
        var currentText = ""
        var currentStart: Int? = nil
        var currentEnd = 0
        var chunkIndex = 0

        func flush() {
            guard let start = currentStart, !currentText.isEmpty else { return }
            chunks.append(TextChunk(
                text: currentText,
                startOffset: start,
                endOffset: currentEnd,
                chunkIndex: chunkIndex,
                metadata: metadata
            ))
            chunkIndex += 1
        }

        for segment in segments {
            if currentText.isEmpty {
                currentText = segment.text
                currentStart = segment.start
                currentEnd = segment.start + segment.text.count
                continue
            }

            // Would appending this segment (with a space) exceed chunkSize?
            let combinedLength = currentText.count + 1 + segment.text.count
            if combinedLength <= chunkSize {
                currentText += "\n" + segment.text
                currentEnd = segment.start + segment.text.count
            } else {
                // Flush current chunk.
                flush()

                // Start next chunk with an overlap tail of the previous chunk
                // to preserve context across boundaries.
                let tail = overlapTail(from: currentText)
                let tailStart = currentEnd - tail.count
                currentText = tail.isEmpty ? segment.text : (tail + "\n" + segment.text)
                currentStart = tail.isEmpty ? segment.start : tailStart
                currentEnd = segment.start + segment.text.count
            }
        }
        flush()

        return chunks
    }

    // MARK: - Helpers

    private struct Segment {
        let text: String
        let start: Int
    }

    private func splitSegments(text: String) -> [Segment] {
        var segments: [Segment] = []
        // Paragraph-first split. Keep track of running offset in chars.
        let nsText = text as NSString
        let length = nsText.length

        // Walk through the text matching paragraph boundaries (two newlines).
        var cursor = 0
        while cursor < length {
            let remaining = NSRange(location: cursor, length: length - cursor)
            let paraEnd: Int
            let nextRange = nsText.range(of: "\n\n", options: [], range: remaining)
            if nextRange.location == NSNotFound {
                paraEnd = length
            } else {
                paraEnd = nextRange.location
            }
            let paraRange = NSRange(location: cursor, length: paraEnd - cursor)
            let paragraph = nsText.substring(with: paraRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                if paragraph.count <= chunkSize {
                    segments.append(Segment(text: paragraph, start: cursor))
                } else {
                    segments.append(contentsOf: splitBySentences(paragraph, baseOffset: cursor))
                }
            }
            if nextRange.location == NSNotFound {
                break
            }
            cursor = nextRange.location + nextRange.length
        }
        return segments
    }

    private func splitBySentences(_ paragraph: String, baseOffset: Int) -> [Segment] {
        // Simple sentence splitter on `.`, `!`, `?`, `。`, `！`, `？` followed by
        // whitespace or end-of-string.
        var segments: [Segment] = []
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
        var current = ""
        var segmentStart = baseOffset
        var localOffset = 0

        for ch in paragraph {
            current.append(ch)
            localOffset += 1
            if terminators.contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if trimmed.count <= chunkSize {
                        segments.append(Segment(text: trimmed, start: segmentStart))
                    } else {
                        segments.append(contentsOf: splitByChars(trimmed, baseOffset: segmentStart))
                    }
                }
                current = ""
                segmentStart = baseOffset + localOffset
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            if tail.count <= chunkSize {
                segments.append(Segment(text: tail, start: segmentStart))
            } else {
                segments.append(contentsOf: splitByChars(tail, baseOffset: segmentStart))
            }
        }
        return segments
    }

    private func splitByChars(_ text: String, baseOffset: Int) -> [Segment] {
        // Fallback: raw character windows sized to chunkSize with no overlap
        // (overlap is added later at the chunk-assembly layer).
        var segments: [Segment] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let end = min(i + chunkSize, chars.count)
            let slice = String(chars[i..<end])
            segments.append(Segment(text: slice, start: baseOffset + i))
            i = end
        }
        return segments
    }

    private func overlapTail(from text: String) -> String {
        guard overlap > 0, text.count > overlap else { return text }
        return String(text.suffix(overlap))
    }
}
