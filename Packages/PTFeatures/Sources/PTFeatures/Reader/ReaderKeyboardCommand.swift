import Foundation

/// Abstracted page-turner used by the reader keyboard handler.
///
/// Real implementations forward to the EPUB navigator coordinator or
/// to `ReaderViewModel.goToPage(_:)` on PDF. Tests can substitute a
/// lightweight stub that records invocations.
@MainActor
public protocol ReaderPageTurner: AnyObject {
    func goNextPage()
    func goPreviousPage()
}

/// Keyboard keys that the reader understands. Intentionally mirrors the
/// subset of `KeyEquivalent` values exposed through SwiftUI's
/// `onKeyPress(_:action:)`.
public enum ReaderKeyboardCommand {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case space
    case pageUp
    case pageDown

    /// Whether the key advances (`true`) or rewinds (`false`) the reader.
    public var advancesPage: Bool {
        switch self {
        case .rightArrow, .downArrow, .space, .pageDown:
            return true
        case .leftArrow, .upArrow, .pageUp:
            return false
        }
    }
}

/// Pure command handler so keyboard navigation behavior can be tested
/// without a live SwiftUI view. The host view calls
/// `handle(_:)` from its `.onKeyPress` closures and returns
/// `.handled` / `.ignored` based on the Bool result.
@MainActor
public struct ReaderKeyboardCommandHandler {
    private weak var pageTurner: (any ReaderPageTurner)?

    public init(pageTurner: any ReaderPageTurner) {
        self.pageTurner = pageTurner
    }

    /// Returns `true` when the command was dispatched. The SwiftUI
    /// caller should translate `true` to `.handled` and `false` to
    /// `.ignored`.
    @discardableResult
    public func handle(_ command: ReaderKeyboardCommand) -> Bool {
        guard let pageTurner else { return false }
        if command.advancesPage {
            pageTurner.goNextPage()
        } else {
            pageTurner.goPreviousPage()
        }
        return true
    }
}
