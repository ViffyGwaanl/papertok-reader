import CoreGraphics
import Foundation

/// Where the floating reader context menu should be anchored relative to the
/// current text selection.
///
/// The reader prefers to anchor the menu above the selection (Apple Books /
/// Kindle convention). When the selection is too close to the top of the
/// reader view, the menu falls back to below the selection. When neither
/// slot fits, the menu is centered on screen.
public enum ContextMenuPlacement: String, CaseIterable, Sendable {
    case above
    case below
    case center

    /// Whether the menu should render a callout arrow pointing at the
    /// selection. Only meaningful for `above` / `below`.
    public var showsCalloutArrow: Bool {
        switch self {
        case .above, .below: return true
        case .center:        return false
        }
    }

    /// Compute the optimal placement for the given selection frame.
    ///
    /// - Parameters:
    ///   - selectionFrame: The selection bounding box in reader coordinates.
    ///     `nil` falls back to `.center`.
    ///   - viewBounds: The size of the reader view that hosts the menu.
    ///   - menuHeight: The height of the menu card (plus any desired margin).
    ///   - margin: Minimum gap (pt) required between the menu and screen edge.
    /// - Returns: `.above` if there is enough room above the selection,
    ///   `.below` if not but there is room below, otherwise `.center`.
    public static func optimal(
        for selectionFrame: CGRect?,
        in viewBounds: CGSize,
        menuHeight: CGFloat = 200,
        margin: CGFloat = 16
    ) -> ContextMenuPlacement {
        guard let frame = selectionFrame, !frame.isNull, !frame.isEmpty else {
            return .center
        }
        let spaceAbove = max(0, frame.minY)
        let spaceBelow = max(0, viewBounds.height - frame.maxY)
        let required = menuHeight + margin
        if spaceAbove >= required { return .above }
        if spaceBelow >= required { return .below }
        return .center
    }

    /// Resolve the top-left origin of the menu card for this placement.
    ///
    /// The menu is horizontally centered over the selection, then clamped to
    /// the view bounds with a small horizontal margin so the card never
    /// clips past a screen edge. Callers pass this into SwiftUI's
    /// `.offset(x:y:)` modifier on a full-bounds container.
    public func menuOrigin(
        for selectionFrame: CGRect,
        in viewBounds: CGSize,
        menuSize: CGSize,
        verticalGap: CGFloat = 8,
        horizontalMargin: CGFloat = 8
    ) -> CGPoint {
        let centeredX = selectionFrame.midX - menuSize.width / 2
        let maxX = max(horizontalMargin, viewBounds.width - menuSize.width - horizontalMargin)
        let clampedX = min(max(centeredX, horizontalMargin), maxX)

        let y: CGFloat
        switch self {
        case .above:
            y = selectionFrame.minY - menuSize.height - verticalGap
        case .below:
            y = selectionFrame.maxY + verticalGap
        case .center:
            y = max(0, (viewBounds.height - menuSize.height) / 2)
        }
        return CGPoint(x: clampedX, y: max(0, y))
    }
}

/// Grouping of context-menu actions into a primary row + a "More…" overflow.
///
/// The primary row shows the four most common actions (note, copy, translate,
/// define). The `More…` sheet surfaces the long-tail actions (explain,
/// summarize, search, share). `.highlight` lives in the annotation color
/// swatches above the action row and is not part of either list.
public enum ContextMenuActionGrouping {
    public static let primaryActions: [ContextMenuAction] = [
        .note, .copy, .translate, .define
    ]

    public static let moreActions: [ContextMenuAction] = [
        .explain, .summarize, .search, .share
    ]
}
