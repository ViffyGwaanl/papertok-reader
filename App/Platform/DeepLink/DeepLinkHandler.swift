import SwiftUI
import PTFeatures

/// View modifier that observes `DeepLinkRouter.pendingDestination`
/// and performs the appropriate navigation.
struct DeepLinkHandlerModifier: ViewModifier {
    @Bindable var router = DeepLinkRouter.shared
    @Binding var selectedTab: AppTab
    @Binding var showImporter: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: router.pendingDestination) { _, destination in
                guard let destination else { return }
                handleDestination(destination)
                router.consumeDestination()
            }
    }

    private func handleDestination(_ destination: DeepLinkDestination) {
        switch destination {
        case .openBook:
            selectedTab = .bookshelf
            // The bookshelf view will check router for a pending book open
        case .aiChat:
            selectedTab = .ai
        case .papers:
            selectedTab = .papers
        case .importFile:
            selectedTab = .bookshelf
            // Slight delay to ensure tab switch completes before presenting importer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showImporter = true
            }
        }
    }
}

extension View {
    /// Attaches deep link handling to the view.
    func handleDeepLinks(selectedTab: Binding<AppTab>, showImporter: Binding<Bool>) -> some View {
        modifier(DeepLinkHandlerModifier(
            selectedTab: selectedTab,
            showImporter: showImporter
        ))
    }
}
