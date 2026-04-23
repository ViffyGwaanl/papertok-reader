import Foundation
import Testing
@testable import PTFeatures

@Suite("Reader keyboard navigation")
@MainActor
struct ReaderKeyboardNavigationTests {
    @Test("leftArrowFiresGoPreviousPage")
    func leftArrowFiresGoPreviousPage() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        let result = handler.handle(.leftArrow)

        #expect(result == true)
        #expect(stub.previousCount == 1)
        #expect(stub.nextCount == 0)
    }

    @Test("rightArrowFiresGoNextPage")
    func rightArrowFiresGoNextPage() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        let result = handler.handle(.rightArrow)

        #expect(result == true)
        #expect(stub.nextCount == 1)
        #expect(stub.previousCount == 0)
    }

    @Test("spaceFiresGoNextPage")
    func spaceFiresGoNextPage() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        let result = handler.handle(.space)

        #expect(result == true)
        #expect(stub.nextCount == 1)
        #expect(stub.previousCount == 0)
    }

    @Test("upArrow maps to previous page")
    func upArrowMapsToPrevious() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        let result = handler.handle(.upArrow)

        #expect(result == true)
        #expect(stub.previousCount == 1)
    }

    @Test("downArrow maps to next page")
    func downArrowMapsToNext() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        let result = handler.handle(.downArrow)

        #expect(result == true)
        #expect(stub.nextCount == 1)
    }

    @Test("pageUpPageDownWork in the expected directions")
    func pageUpPageDownWork() {
        let stub = StubReaderPageTurner()
        let handler = ReaderKeyboardCommandHandler(pageTurner: stub)

        _ = handler.handle(.pageUp)
        _ = handler.handle(.pageDown)

        #expect(stub.previousCount == 1)
        #expect(stub.nextCount == 1)
    }
}

@MainActor
final class StubReaderPageTurner: ReaderPageTurner {
    var nextCount = 0
    var previousCount = 0

    func goNextPage() {
        nextCount += 1
    }

    func goPreviousPage() {
        previousCount += 1
    }
}
