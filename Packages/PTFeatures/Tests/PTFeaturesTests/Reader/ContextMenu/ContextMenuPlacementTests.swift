import CoreGraphics
import Foundation
import Testing
@testable import PTFeatures

@Suite("ContextMenu placement")
struct ContextMenuPlacementTests {

    @Test("placement is above when there is enough space above the selection")
    func placementIsAboveWhenSpaceAvailable() {
        // 400pt of space above, way more than the 200pt menu + 16pt margin.
        let selection = CGRect(x: 40, y: 400, width: 220, height: 40)
        let bounds = CGSize(width: 390, height: 844)

        let placement = ContextMenuPlacement.optimal(
            for: selection,
            in: bounds,
            menuHeight: 200
        )

        #expect(placement == .above)
    }

    @Test("placement is below when no space above the selection")
    func placementIsBelowWhenNoSpaceAbove() {
        // Selection near the top: only 10pt above, not enough for a 200pt menu.
        let selection = CGRect(x: 40, y: 10, width: 220, height: 40)
        let bounds = CGSize(width: 390, height: 844)

        let placement = ContextMenuPlacement.optimal(
            for: selection,
            in: bounds,
            menuHeight: 200
        )

        #expect(placement == .below)
    }

    @Test("placement is center when neither above nor below has room")
    func placementIsCenterWhenNoRoom() {
        // Bounds too short for a 200pt menu to sit above OR below.
        let selection = CGRect(x: 40, y: 90, width: 220, height: 40)
        let bounds = CGSize(width: 390, height: 220)

        let placement = ContextMenuPlacement.optimal(
            for: selection,
            in: bounds,
            menuHeight: 200
        )

        #expect(placement == .center)
    }

    @Test("placement handles a nil selection frame by returning center")
    func placementHandlesNilSelection() {
        let placement = ContextMenuPlacement.optimal(
            for: nil,
            in: CGSize(width: 390, height: 844),
            menuHeight: 200
        )

        #expect(placement == .center)
    }

    @Test("callout arrow is hidden for center placement")
    func calloutArrowIsHiddenForCenterPlacement() {
        #expect(ContextMenuPlacement.center.showsCalloutArrow == false)
        #expect(ContextMenuPlacement.above.showsCalloutArrow == true)
        #expect(ContextMenuPlacement.below.showsCalloutArrow == true)
    }

    @Test("above placement offsets the menu so its bottom sits above the selection")
    func abovePlacementOffsetAnchorsAboveSelection() {
        let selection = CGRect(x: 40, y: 400, width: 220, height: 40)
        let bounds = CGSize(width: 390, height: 844)
        let menuSize = CGSize(width: 300, height: 200)

        let offset = ContextMenuPlacement.above.menuOrigin(
            for: selection,
            in: bounds,
            menuSize: menuSize
        )

        // Menu bottom = selection.minY - 8
        #expect(offset.y + menuSize.height <= selection.minY)
    }

    @Test("below placement offsets the menu so its top sits below the selection")
    func belowPlacementOffsetAnchorsBelowSelection() {
        let selection = CGRect(x: 40, y: 10, width: 220, height: 40)
        let bounds = CGSize(width: 390, height: 844)
        let menuSize = CGSize(width: 300, height: 200)

        let offset = ContextMenuPlacement.below.menuOrigin(
            for: selection,
            in: bounds,
            menuSize: menuSize
        )

        #expect(offset.y >= selection.maxY)
    }
}
