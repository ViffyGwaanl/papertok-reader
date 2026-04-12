import Foundation
import Testing
import PTFeatures
@testable import PaperTokReader

@Suite("DeepLinkRouter")
struct DeepLinkRouterTests {
    @Test("AI share token URLs route into an AI share request")
    func aiShareTokenURL() {
        let url = URL(string: "paperreader://ai?share_token=share-event-1")!
        let destination = DeepLinkParser.parse(url: url)

        #expect(destination == .aiChat(initialMessage: nil, shareToken: "share-event-1"))
    }

    @Test("import token URLs still route to bookshelf import")
    func importTokenURL() {
        let url = URL(string: "paperreader://import?token=share-event-2")!
        let destination = DeepLinkParser.parse(url: url)

        #expect(destination == .importFile(token: "share-event-2"))
    }

    @Test("reader open URLs use the bookId query instead of the literal open path segment")
    func readerOpenURLUsesQueryBookID() {
        let url = URL(string: "paperreader://reader/open?bookId=42&href=Text%2Fchapter-1.xhtml")!
        let destination = DeepLinkParser.parse(url: url)

        #expect(destination == .openBook(id: "42", title: nil, locator: "Text/chapter-1.xhtml"))
    }

    @Test("shortcut ask URLs keep a distinct quick ask destination")
    func quickAskShareTokenURL() {
        let url = URL(string: "paperreader://shortcuts/ask?share_token=share-event-4")!
        let destination = DeepLinkParser.parse(url: url)

        #expect(destination == .quickAsk(initialMessage: nil, shareToken: "share-event-4"))
    }

    @Test("existing pending destinations are consumed into navigation state")
    func existingPendingDestinationIsConsumed() {
        let router = DeepLinkRouter.shared
        router.pendingDestination = .aiChat(initialMessage: "hello", shareToken: "share-event-3")
        defer { router.consumeDestination() }

        var selectedTab: AppTab = .bookshelf
        var pendingBookRequest: BookshelfOpenRequest?
        var pendingAIRequest: AIChatOpenRequest?
        var sharedInboxImportRequest: SharedInboxImportRequest?

        RootNavigationCoordinator.consumePendingDestinationIfNeeded(
            router: router,
            selectedTab: &selectedTab,
            pendingBookRequest: &pendingBookRequest,
            pendingAIRequest: &pendingAIRequest,
            sharedInboxImportRequest: &sharedInboxImportRequest
        )

        #expect(selectedTab == .ai)
        #expect(pendingBookRequest == nil)
        #expect(sharedInboxImportRequest == nil)
        #expect(pendingAIRequest?.message == "hello")
        #expect(pendingAIRequest?.shareEventID == "share-event-3")
        #expect(router.pendingDestination == nil)
    }

    @Test("switching destinations clears stale navigation requests")
    func consumingDestinationClearsStaleRequests() {
        let router = DeepLinkRouter.shared
        router.pendingDestination = .papers
        defer { router.consumeDestination() }

        var selectedTab: AppTab = .bookshelf
        var pendingBookRequest: BookshelfOpenRequest? = .init(bookID: "7", title: "Old Book")
        var pendingAIRequest: AIChatOpenRequest? = .init(message: "old question", shareEventID: "share-event-old")
        var sharedInboxImportRequest: SharedInboxImportRequest? = .init(eventID: "share-event-import")

        RootNavigationCoordinator.consumePendingDestinationIfNeeded(
            router: router,
            selectedTab: &selectedTab,
            pendingBookRequest: &pendingBookRequest,
            pendingAIRequest: &pendingAIRequest,
            sharedInboxImportRequest: &sharedInboxImportRequest
        )

        #expect(selectedTab == .papers)
        #expect(pendingBookRequest == nil)
        #expect(pendingAIRequest == nil)
        #expect(sharedInboxImportRequest == nil)
        #expect(router.pendingDestination == nil)
    }
}
