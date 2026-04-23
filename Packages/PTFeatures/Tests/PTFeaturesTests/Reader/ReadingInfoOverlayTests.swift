import Foundation
import Testing
@testable import PTFeatures
import PTCore

@Suite("ReadingInfoOverlay")
struct ReadingInfoOverlayTests {
    private func makeContext(currentTime: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ReadingInfoContext {
        ReadingInfoContext(
            chapterTitle: "Chapter 3",
            pageNumber: 42,
            totalPages: 247,
            progressPercentage: 0.17,
            readingTime: 4_980, // 1h 23m
            batteryLevel: 0.87,
            currentTime: currentTime
        )
    }

    @Test("Field helper renders correct text for each case")
    @MainActor
    func fieldHelperRendersCorrectTextForEachCase() {
        let context = makeContext()
        #expect(ReadingInfoOverlay.render(field: .nothing, context: context) == "")
        #expect(ReadingInfoOverlay.render(field: .chapterTitle, context: context) == "Chapter 3")
        #expect(ReadingInfoOverlay.render(field: .pageNumber, context: context) == "42 / 247")
        #expect(ReadingInfoOverlay.render(field: .progressPercentage, context: context) == "17%")
        #expect(ReadingInfoOverlay.render(field: .readingTime, context: context) == "1h 23m")
        #expect(ReadingInfoOverlay.render(field: .batteryLevel, context: context) == "87%")
        // Clock uses a fixed `HH:mm` formatter — just confirm colon shape.
        let clock = ReadingInfoOverlay.render(field: .clock, context: context)
        #expect(clock.count == 5)
        #expect(clock.contains(":"))
    }

    @Test("Layout positions fields correctly across top and bottom rows")
    @MainActor
    func layoutPositionsFieldsCorrectly() {
        let layout = ReadingInfoLayout(
            topLeft: .clock,
            topCenter: .chapterTitle,
            topRight: .batteryLevel,
            bottomLeft: .pageNumber,
            bottomCenter: .readingTime,
            bottomRight: .progressPercentage
        )
        // Verify slot assignments survive as-is (no reordering).
        #expect(layout.topLeft == .clock)
        #expect(layout.topCenter == .chapterTitle)
        #expect(layout.topRight == .batteryLevel)
        #expect(layout.bottomLeft == .pageNumber)
        #expect(layout.bottomCenter == .readingTime)
        #expect(layout.bottomRight == .progressPercentage)

        // Sanity check: the overlay builds without crashing.
        let overlay = ReadingInfoOverlay(layout: layout, context: makeContext(), isVisible: true)
        _ = overlay.body
    }

    @Test("Nothing field renders as empty string")
    @MainActor
    func nothingFieldRendersAsInvisible() {
        let context = makeContext()
        #expect(ReadingInfoOverlay.render(field: .nothing, context: context) == "")
        #expect(ReadingInfoOverlay.accessibilityLabel(for: .nothing, context: context) == "")
    }

    @Test("Reading time formatting handles sub-minute, minute, and hour cases")
    @MainActor
    func readingTimeFormatting() {
        var context = makeContext()
        context = ReadingInfoContext(
            chapterTitle: context.chapterTitle,
            pageNumber: context.pageNumber,
            totalPages: context.totalPages,
            progressPercentage: context.progressPercentage,
            readingTime: 30, // <1m
            batteryLevel: context.batteryLevel,
            currentTime: context.currentTime
        )
        #expect(ReadingInfoOverlay.render(field: .readingTime, context: context) == "<1m")

        let fiveMin = ReadingInfoContext(readingTime: 5 * 60, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .readingTime, context: fiveMin) == "5m")

        let twoHours = ReadingInfoContext(readingTime: 2 * 3600 + 5 * 60, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .readingTime, context: twoHours) == "2h 5m")
    }

    @Test("Page number falls back to bare count when total is missing")
    @MainActor
    func pageNumberFallback() {
        let ctx = ReadingInfoContext(pageNumber: 42, totalPages: nil, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .pageNumber, context: ctx) == "42")

        let none = ReadingInfoContext(pageNumber: nil, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .pageNumber, context: none) == "")
    }

    @Test("Progress percentage clamps 0..1 and renders integer percent")
    @MainActor
    func progressClamping() {
        let low = ReadingInfoContext(progressPercentage: -0.25, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .progressPercentage, context: low) == "0%")

        let high = ReadingInfoContext(progressPercentage: 1.42, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .progressPercentage, context: high) == "100%")
    }

    @Test("Battery level renders 0..100 percentage and skips negative values")
    @MainActor
    func batteryFormatting() {
        let unavailable = ReadingInfoContext(batteryLevel: -1.0, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .batteryLevel, context: unavailable) == "")

        let half = ReadingInfoContext(batteryLevel: 0.5, currentTime: Date())
        #expect(ReadingInfoOverlay.render(field: .batteryLevel, context: half) == "50%")
    }

    @Test("Accessibility label combines localized field name with value")
    @MainActor
    func accessibilityLabel() {
        let ctx = makeContext()
        let label = ReadingInfoOverlay.accessibilityLabel(for: .pageNumber, context: ctx)
        #expect(label.contains("42 / 247"))
        #expect(label.contains(":"))
    }
}
