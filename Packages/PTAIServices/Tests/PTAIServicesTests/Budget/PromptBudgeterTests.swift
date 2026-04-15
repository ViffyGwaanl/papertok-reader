import Testing
import Foundation
@testable import PTAIServices

@Suite("PromptBudgeter")
struct PromptBudgeterTests {
    private static let marker = "[truncated]"

    @Test("messages under limit are pass-through")
    func messagesUnderLimitArePassThrough() {
        let b = PromptBudgeter(maxCharactersPerMessage: 1_000, truncationMarker: Self.marker)
        let messages: [ChatMessage] = [.user("hello"), .assistant("hi there")]
        let result = b.budget(messages)
        #expect(result.wasTruncated == false)
        #expect(result.messages == messages)
        #expect(result.originalCharacterCount == result.finalCharacterCount)
    }

    @Test("oversized message is truncated")
    func oversizedMessageIsTruncated() {
        let b = PromptBudgeter(maxCharactersPerMessage: 100, truncationMarker: Self.marker)
        let big = String(repeating: "a", count: 500)
        let result = b.budget([.user(big)])
        #expect(result.wasTruncated == true)
        let text = result.messages[0].textContent ?? ""
        #expect(text.count <= 100 + Self.marker.count)
        #expect(text.hasSuffix(Self.marker))
    }

    @Test("truncation cuts at whitespace boundary")
    func truncationCutsAtWhitespaceBoundary() {
        let b = PromptBudgeter(maxCharactersPerMessage: 20, truncationMarker: Self.marker)
        // 20-char window: "one two three four f"  -> last whitespace before 20 is after "four"
        let text = "one two three four five six seven eight"
        let result = b.budget([.user(text)])
        #expect(result.wasTruncated == true)
        let clipped = result.messages[0].textContent ?? ""
        #expect(clipped.hasPrefix("one two three four"))
        #expect(clipped.hasSuffix(Self.marker))
    }

    @Test("truncation appends marker")
    func truncationAppendsMarker() {
        let b = PromptBudgeter(maxCharactersPerMessage: 10, truncationMarker: Self.marker)
        let result = b.budget([.user(String(repeating: "x", count: 1_000))])
        #expect((result.messages[0].textContent ?? "").hasSuffix(Self.marker))
    }

    @Test("truncation discards subsequent content parts")
    func truncationDiscardsSubsequentContentParts() {
        let b = PromptBudgeter(maxCharactersPerMessage: 5, truncationMarker: Self.marker)
        let parts: [ContentPart] = [
            .text(String(repeating: "a", count: 100)),
            .text("should-be-dropped"),
            .imageURL("https://example.com/x.png")
        ]
        let msg = ChatMessage(role: .user, content: parts)
        let result = b.budget([msg])
        let outParts = result.messages[0].content
        #expect(outParts.count == 1)
        if case .text(let t) = outParts[0] {
            #expect(t.hasSuffix(Self.marker))
            #expect(t.contains("should-be-dropped") == false)
        } else {
            Issue.record("expected text part")
        }
    }

    @Test("wasTruncated flag set correctly")
    func wasTruncatedFlagSetCorrectly() {
        let b = PromptBudgeter(maxCharactersPerMessage: 50, truncationMarker: Self.marker)
        let small = b.budget([.user("short")])
        #expect(small.wasTruncated == false)
        let big = b.budget([.user(String(repeating: "a", count: 200))])
        #expect(big.wasTruncated == true)
    }

    @Test("original character count reported accurately")
    func originalCharacterCountReportedAccurately() {
        let b = PromptBudgeter(maxCharactersPerMessage: 10, truncationMarker: Self.marker)
        let result = b.budget([
            .user(String(repeating: "a", count: 500)),
            .assistant("hi")
        ])
        #expect(result.originalCharacterCount == 502)
        #expect(result.finalCharacterCount < result.originalCharacterCount)
    }
}
