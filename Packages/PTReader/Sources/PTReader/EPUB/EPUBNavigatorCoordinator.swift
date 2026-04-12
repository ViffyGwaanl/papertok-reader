#if canImport(UIKit)
import Foundation
import CoreGraphics
import Observation
import ReadiumNavigator
import ReadiumShared
import WebKit

/// @Observable coordinator that bridges EPUBNavigatorViewController state to SwiftUI.
///
/// Manages current locator (chapter + position), pending annotation creation,
/// and user navigation events (tap to flip page, TOC jump).
@Observable
@MainActor
public final class EPUBNavigatorCoordinator: NSObject {
    // MARK: - Published state

    public private(set) var currentLocator: Locator?
    public private(set) var currentChapterTitle: String = ""
    public private(set) var readingProgress: Double = 0 // 0.0-1.0

    // MARK: - Pending selection (for annotation creation)

    public var selectedText: String = ""
    public var selectedLocator: Locator?
    public var selectedFrame: CGRect?

    // MARK: - Delegate callbacks

    public var onLocatorChange: ((Locator) -> Void)?
    public var onHighlightRequest: ((Locator, String) -> Void)? // locator, selectedText
    public var onSelectionChange: ((Locator, String, CGRect?) -> Void)?
    public var onDecorationActivated: ((OnDecorationActivatedEvent) -> Void)?
    public var onImageActivate: ((ReaderImageAsset) -> Void)?

    // MARK: - Internal

    private var pendingDecorationsByGroup: [String: [Decoration]] = [:]
    private var decorationCallbacksByGroup: [String: [(OnDecorationActivatedEvent) -> Void]] = [:]
    private var observedDecorationGroups: Set<String> = []
    private var readingPreferencesSnapshot = EPUBReadingPreferencesSnapshot(readingPreferences: ReadingPreferences())

    weak var navigatorViewController: EPUBNavigatorViewController? {
        didSet {
            observedDecorationGroups.removeAll()
            flushNavigatorState()
            applyReadingPreferencesIfNeeded()
        }
    }

    public override init() {
        super.init()
    }

    public func navigate(to locator: Locator) {
        Task { @MainActor [weak self] in
            _ = await self?.navigatorViewController?.go(to: locator)
        }
    }

    public func goForward() {
        Task { @MainActor [weak self] in
            _ = await self?.navigatorViewController?.goForward(options: NavigatorGoOptions(animated: true))
        }
    }

    public func goBackward() {
        Task { @MainActor [weak self] in
            _ = await self?.navigatorViewController?.goBackward(options: NavigatorGoOptions(animated: true))
        }
    }

    public func applyDecorations(_ decorations: [Decoration], in group: String) {
        pendingDecorationsByGroup[group] = decorations
        navigatorViewController?.apply(decorations: decorations, in: group)
    }

    public func observeDecorationInteractions(
        inGroup group: String,
        onActivated: @escaping (OnDecorationActivatedEvent) -> Void
    ) {
        decorationCallbacksByGroup[group, default: []].append(onActivated)
        registerDecorationInteractionsIfNeeded(for: group)
    }

    public func clearSelection() {
        navigatorViewController?.clearSelection()
        selectedText = ""
        selectedLocator = nil
        selectedFrame = nil
    }

    public func handleImageMessage(_ body: Any) {
        guard let asset = EPUBImageScriptBridge.asset(from: body) else {
            return
        }
        onImageActivate?(asset)
    }

    public func setReadingPreferences(_ snapshot: EPUBReadingPreferencesSnapshot) {
        guard readingPreferencesSnapshot != snapshot else {
            return
        }
        readingPreferencesSnapshot = snapshot
        applyReadingPreferencesIfNeeded()
    }

    private func flushNavigatorState() {
        guard navigatorViewController != nil else {
            return
        }

        for (group, decorations) in pendingDecorationsByGroup {
            navigatorViewController?.apply(decorations: decorations, in: group)
            registerDecorationInteractionsIfNeeded(for: group)
        }

        for group in decorationCallbacksByGroup.keys {
            registerDecorationInteractionsIfNeeded(for: group)
        }
    }

    private func registerDecorationInteractionsIfNeeded(for group: String) {
        guard let navigatorViewController,
              observedDecorationGroups.contains(group) == false else {
            return
        }

        navigatorViewController.observeDecorationInteractions(inGroup: group) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onDecorationActivated?(event)
                for callback in self.decorationCallbacksByGroup[group] ?? [] {
                    callback(event)
                }
            }
        }
        observedDecorationGroups.insert(group)
    }

    private func applyReadingPreferencesIfNeeded() {
        guard let navigatorViewController else {
            return
        }
        navigatorViewController.submitPreferences(readingPreferencesSnapshot.preferences)
        navigatorViewController.view.setNeedsLayout()
        navigatorViewController.view.layoutIfNeeded()
    }
}

// MARK: - EPUBNavigatorDelegate

extension EPUBNavigatorCoordinator: EPUBNavigatorDelegate {
    public func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        readingPreferencesSnapshot.contentInsets
    }

    public func navigator(_ navigator: EPUBNavigatorViewController, viewportDidChange viewport: EPUBNavigatorViewController.Viewport?) {
        // Optional: handle viewport changes
    }

    public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
        userContentController.removeScriptMessageHandler(forName: EPUBImageScriptBridge.messageHandlerName)
        userContentController.addUserScript(EPUBImageScriptBridge.makeUserScript())
        userContentController.add(self, name: EPUBImageScriptBridge.messageHandlerName)
    }

    public nonisolated func navigator(_ navigator: any Navigator, locationDidChange locator: Locator) {
        Task { @MainActor [weak self] in
            self?.currentLocator = locator
            self?.currentChapterTitle = locator.title ?? ""
            self?.readingProgress = locator.locations.totalProgression ?? locator.locations.progression ?? 0
            self?.onLocatorChange?(locator)
        }
    }

    public nonisolated func navigator(_ navigator: any Navigator, didJumpTo locator: Locator) {
        // Optional: handle explicit jumps (e.g. for navigation history)
    }

    public nonisolated func navigator(_ navigator: any Navigator, presentError error: NavigatorError) {
        // Handle navigator errors (e.g. DRM copy forbidden)
    }

    public nonisolated func navigator(_ navigator: any Navigator, presentExternalURL url: URL) {
        // Handle external URL opening
    }

    public nonisolated func navigator(_ navigator: any Navigator, shouldNavigateToNoteAt link: Link, content: String, referrer: String?) -> Bool {
        true
    }

    public nonisolated func navigator(_ navigator: any Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        // Handle resource load failures
    }
}

// MARK: - SelectableNavigatorDelegate

extension EPUBNavigatorCoordinator: SelectableNavigatorDelegate {
    public func navigator(_ navigator: any SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
        let highlightedText = selection.locator.text.highlight ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.selectedText = highlightedText
            self.selectedLocator = selection.locator
            self.selectedFrame = selection.frame
            guard highlightedText.isEmpty == false else { return }
            self.onHighlightRequest?(selection.locator, highlightedText)
            self.onSelectionChange?(selection.locator, highlightedText, selection.frame)
        }
        return highlightedText.isEmpty
    }

    public func navigator(_ navigator: any SelectableNavigator, canPerformAction action: EditingAction, for selection: Selection) -> Bool {
        true
    }
}

extension EPUBNavigatorCoordinator: WKScriptMessageHandler {
    public nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == EPUBImageScriptBridge.messageHandlerName else {
            return
        }
        Task { @MainActor [weak self] in
            self?.handleImageMessage(message.body)
        }
    }
}
#endif
