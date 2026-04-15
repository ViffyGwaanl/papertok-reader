import Testing
import Foundation
@testable import PTAIServices

@Suite("ChatMessageCitations")
struct ChatMessageCitationsTests {
    @Test("Citations round-trip through Codable")
    func citationsRoundTripThroughCodable() throws {
        let citations = [
            MessageCitation(index: 1, title: "Paper A", url: URL(string: "https://example.com/a"), snippet: "snippet a"),
            MessageCitation(index: 2, title: "Paper B", url: URL(string: "https://example.com/b"), snippet: nil)
        ]
        let msg = ChatMessage.assistant("See [1] and [2]", citations: citations)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(decoded.citations.count == 2)
        #expect(decoded.citations[0].title == "Paper A")
        #expect(decoded.citations[0].index == 1)
        #expect(decoded.citations[1].snippet == nil)
        #expect(decoded == msg)
    }

    @Test("Old format without citations decodes with empty array")
    func oldFormatWithoutCitationsLoadsWithEmpty() throws {
        let msg = ChatMessage.assistant("Hello world")
        let data = try JSONEncoder().encode(msg)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "citations")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: stripped)
        #expect(decoded.citations.isEmpty)
        #expect(decoded.textContent == "Hello world")
    }

    @Test("Default factory produces empty citations")
    func defaultFactoriesEmpty() {
        #expect(ChatMessage.user("hi").citations.isEmpty)
        #expect(ChatMessage.assistant("hi").citations.isEmpty)
        #expect(ChatMessage.system("hi").citations.isEmpty)
    }
}
