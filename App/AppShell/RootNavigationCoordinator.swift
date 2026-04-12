import Observation
import SwiftUI
import PTFeatures

struct BookshelfOpenRequest: Equatable {
    let bookID: String?
    let title: String?
}

struct AIChatOpenRequest: Equatable, Identifiable {
    let id = UUID()
    let message: String?
    let shareEventID: String?
}

struct SharedInboxImportRequest: Equatable, Identifiable {
    let id = UUID()
    let eventID: String?
}

@Observable
final class RootNavigationCoordinator {
    var selectedTab: AppTab = .bookshelf
    var pendingBookRequest: BookshelfOpenRequest?
    var pendingAIRequest: AIChatOpenRequest?
    var sharedInboxImportRequest: SharedInboxImportRequest?

    /// Optional binding wrapper for use with `List(selection:)` on iPad/macOS.
    var optionalSelectedTab: AppTab? {
        get { selectedTab }
        set { if let newValue { selectedTab = newValue } }
    }

    func consumePendingDestinationIfNeeded(router: DeepLinkRouter = .shared) {
        Self.consumePendingDestinationIfNeeded(
            router: router,
            selectedTab: &selectedTab,
            pendingBookRequest: &pendingBookRequest,
            pendingAIRequest: &pendingAIRequest,
            sharedInboxImportRequest: &sharedInboxImportRequest
        )
    }

    static func consumePendingDestinationIfNeeded(
        router: DeepLinkRouter,
        selectedTab: inout AppTab,
        pendingBookRequest: inout BookshelfOpenRequest?,
        pendingAIRequest: inout AIChatOpenRequest?,
        sharedInboxImportRequest: inout SharedInboxImportRequest?
    ) {
        guard let destination = router.pendingDestination else { return }
        applyDestination(
            destination,
            selectedTab: &selectedTab,
            pendingBookRequest: &pendingBookRequest,
            pendingAIRequest: &pendingAIRequest,
            sharedInboxImportRequest: &sharedInboxImportRequest
        )
        router.consumeDestination()
    }

    private static func applyDestination(
        _ destination: DeepLinkDestination,
        selectedTab: inout AppTab,
        pendingBookRequest: inout BookshelfOpenRequest?,
        pendingAIRequest: inout AIChatOpenRequest?,
        sharedInboxImportRequest: inout SharedInboxImportRequest?
    ) {
        pendingBookRequest = nil
        pendingAIRequest = nil
        sharedInboxImportRequest = nil

        switch destination {
        case .openBook(let id, let title, _):
            selectedTab = .bookshelf
            pendingBookRequest = BookshelfOpenRequest(bookID: id, title: title)
        case .aiChat(let initialMessage, let shareToken):
            selectedTab = .ai
            pendingAIRequest = AIChatOpenRequest(message: initialMessage, shareEventID: shareToken)
        case .quickAsk(let initialMessage, let shareToken):
            selectedTab = .ai
            pendingAIRequest = AIChatOpenRequest(message: initialMessage, shareEventID: shareToken)
        case .papers:
            selectedTab = .papers
        case .importFile(let token):
            selectedTab = .bookshelf
            sharedInboxImportRequest = SharedInboxImportRequest(eventID: token)
        }
    }
}

struct RootNavigationCoordinatorModifier: ViewModifier {
    @Bindable var router = DeepLinkRouter.shared
    @Bindable var navigation: RootNavigationCoordinator

    func body(content: Content) -> some View {
        content
            .task(id: router.pendingDestination) {
                navigation.consumePendingDestinationIfNeeded(router: router)
            }
    }
}

extension View {
    func handleDeepLinks(navigation: RootNavigationCoordinator) -> some View {
        modifier(RootNavigationCoordinatorModifier(navigation: navigation))
    }
}
