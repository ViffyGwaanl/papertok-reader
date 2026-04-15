import Testing
import Foundation
@testable import PTFeatures
import PTAIServices

@Suite("MessageBubbleCitationsWiring")
struct MessageBubbleCitationsWiringTests {

    @Test("assistant bubble shows footer when citations present")
    func assistantBubbleWithCitationsExposesFooter() {
        let message = ChatMessage.assistant(
            "Fact [1].",
            citations: [MessageCitation(index: 1, title: "Source A")]
        )
        #expect(MessageBubbleView.shouldShowCitationsFooter(for: message) == true)
    }

    @Test("assistant bubble hides footer when citations empty")
    func assistantBubbleWithEmptyCitationsHidesFooter() {
        let message = ChatMessage.assistant("Plain body.")
        #expect(MessageBubbleView.shouldShowCitationsFooter(for: message) == false)
    }

    @Test("user bubble never shows citations footer")
    func userBubbleNeverShowsCitationsFooter() {
        let message = ChatMessage.user(
            "Question [1]?",
            citations: [MessageCitation(index: 1, title: "Source A")]
        )
        #expect(MessageBubbleView.shouldShowCitationsFooter(for: message) == false)
    }

    @Test("markdown renderer applies citation markers to assistant body")
    func markdownRendererIsAppliedToAssistantBody() {
        let attributed = MessageBubbleView.assistantAttributedBody(for: "Fact [1] and [2].")
        var raisedRuns = 0
        for run in attributed.runs where (run.baselineOffset ?? 0) > 0 {
            raisedRuns += 1
        }
        #expect(raisedRuns >= 2)
    }
}
