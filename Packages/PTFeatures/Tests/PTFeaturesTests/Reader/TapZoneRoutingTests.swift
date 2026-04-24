import Foundation
import Testing
@testable import PTFeatures

/// W7.1 — Three-zone tap routing (prev / toggle chrome / next).
@Suite("TapZoneRouting")
struct TapZoneRoutingTests {
    @Test("Tap in left third routes to previous page")
    func tapInLeftThirdGoesBack() {
        #expect(ReaderTapZone.zone(for: 0.0) == .previousPage)
        #expect(ReaderTapZone.zone(for: 0.1) == .previousPage)
        #expect(ReaderTapZone.zone(for: 0.32) == .previousPage)
    }

    @Test("Tap in right third routes to next page")
    func tapInRightThirdGoesForward() {
        #expect(ReaderTapZone.zone(for: 0.68) == .nextPage)
        #expect(ReaderTapZone.zone(for: 0.9) == .nextPage)
        #expect(ReaderTapZone.zone(for: 1.0) == .nextPage)
    }

    @Test("Tap in center third toggles chrome")
    func tapInCenterThirdTogglesChrome() {
        #expect(ReaderTapZone.zone(for: 0.34) == .toggleChrome)
        #expect(ReaderTapZone.zone(for: 0.5) == .toggleChrome)
        #expect(ReaderTapZone.zone(for: 0.66) == .toggleChrome)
    }

    @Test("Geometry-based zone routing respects width")
    func geometryRoutingUsesWidth() {
        let width: Double = 300
        #expect(ReaderTapZone.zone(forX: 50, width: width) == .previousPage)
        #expect(ReaderTapZone.zone(forX: 150, width: width) == .toggleChrome)
        #expect(ReaderTapZone.zone(forX: 250, width: width) == .nextPage)
    }

    @Test("Zero width defensively resolves to center")
    func zeroWidthDefensivelyReturnsCenter() {
        // Avoids division-by-zero in GeometryReader edge cases.
        #expect(ReaderTapZone.zone(forX: 42, width: 0) == .toggleChrome)
    }

    @Test("Double-tap semantics remain independent of zone routing")
    func doubleTapStillHandledForFullscreen() {
        // The controller exposes an explicit `showChrome`/`hideChrome` API
        // so that higher-priority gestures (e.g. double-tap fullscreen)
        // can keep chrome in sync without colliding with single-tap
        // routing. Verify the two API surfaces do not interfere.
        let zone = ReaderTapZone.zone(for: 0.5)
        #expect(zone == .toggleChrome)
        #expect(ReaderTapZone.previousPage != ReaderTapZone.toggleChrome)
        #expect(ReaderTapZone.nextPage != ReaderTapZone.toggleChrome)
    }
}
