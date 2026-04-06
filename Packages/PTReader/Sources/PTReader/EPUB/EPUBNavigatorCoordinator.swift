#if canImport(UIKit)
import Foundation
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

    // MARK: - Delegate callbacks

    public var onLocatorChange: ((Locator) -> Void)?
    public var onHighlightRequest: ((Locator, String) -> Void)? // locator, selectedText

    // MARK: - Internal

    weak var navigatorViewController: EPUBNavigatorViewController?

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
}

// MARK: - EPUBNavigatorDelegate

extension EPUBNavigatorCoordinator: EPUBNavigatorDelegate {
    public func navigator(_ navigator: EPUBNavigatorViewController, viewportDidChange viewport: EPUBNavigatorViewController.Viewport?) {
        // Optional: handle viewport changes
    }

    public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
        // Optional: inject custom JS
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
        Task { @MainActor [weak self] in
            self?.selectedText = selection.locator.text.highlight ?? ""
            self?.selectedLocator = selection.locator
        }
        return true
    }

    public func navigator(_ navigator: any SelectableNavigator, canPerformAction action: EditingAction, for selection: Selection) -> Bool {
        true
    }
}
#endif
