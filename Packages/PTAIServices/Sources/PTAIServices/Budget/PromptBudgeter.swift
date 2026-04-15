import Foundation

public struct PromptBudgeter: Sendable {
    public let maxCharactersPerMessage: Int
    public let truncationMarker: String

    public init(maxCharactersPerMessage: Int = 60_000, truncationMarker: String) {
        self.maxCharactersPerMessage = maxCharactersPerMessage
        self.truncationMarker = truncationMarker
    }

    public struct Result: Sendable, Equatable {
        public let messages: [ChatMessage]
        public let wasTruncated: Bool
        public let originalCharacterCount: Int
        public let finalCharacterCount: Int

        public init(
            messages: [ChatMessage],
            wasTruncated: Bool,
            originalCharacterCount: Int,
            finalCharacterCount: Int
        ) {
            self.messages = messages
            self.wasTruncated = wasTruncated
            self.originalCharacterCount = originalCharacterCount
            self.finalCharacterCount = finalCharacterCount
        }
    }

    public func budget(_ messages: [ChatMessage]) -> Result {
        var out: [ChatMessage] = []
        out.reserveCapacity(messages.count)
        var wasTruncated = false
        var originalTotal = 0
        var finalTotal = 0

        for message in messages {
            let originalChars = Self.characterCount(of: message.content)
            originalTotal += originalChars

            if originalChars <= maxCharactersPerMessage {
                finalTotal += originalChars
                out.append(message)
                continue
            }

            var remaining = maxCharactersPerMessage
            var newParts: [ContentPart] = []
            newParts.reserveCapacity(message.content.count)
            var truncatedHere = false

            for part in message.content {
                if truncatedHere { break }
                switch part {
                case .text(let text):
                    let len = text.count
                    if len <= remaining {
                        newParts.append(.text(text))
                        remaining -= len
                    } else {
                        let clipped = Self.clipText(text, limit: remaining)
                        newParts.append(.text(clipped + truncationMarker))
                        truncatedHere = true
                        remaining = 0
                    }
                case .imageURL, .imageBase64:
                    newParts.append(part)
                }
            }

            wasTruncated = wasTruncated || truncatedHere
            let rebuilt = ChatMessage(
                id: message.id,
                role: message.role,
                content: newParts,
                toolCallId: message.toolCallId,
                toolCalls: message.toolCalls,
                citations: message.citations
            )
            finalTotal += Self.characterCount(of: rebuilt.content)
            out.append(rebuilt)
        }

        return Result(
            messages: out,
            wasTruncated: wasTruncated,
            originalCharacterCount: originalTotal,
            finalCharacterCount: finalTotal
        )
    }

    private static func characterCount(of parts: [ContentPart]) -> Int {
        var total = 0
        for part in parts {
            if case .text(let t) = part {
                total += t.count
            }
        }
        return total
    }

    private static func clipText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        if text.count <= limit { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        let window = text[text.startIndex..<endIndex]
        var lastWhitespace: String.Index? = nil
        var i = window.startIndex
        while i < window.endIndex {
            if window[i].isWhitespace {
                lastWhitespace = i
            }
            i = window.index(after: i)
        }
        if let lastWhitespace {
            return String(text[text.startIndex..<lastWhitespace])
        }
        return String(window)
    }
}
