import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("ReaderFindBarState")
@MainActor
struct ReaderFindBarStateTests {
    private func makeHit(_ snippet: String, page: Int? = nil) -> ReaderSearchHit {
        ReaderSearchHit(
            snippet: snippet,
            locator: ReaderSearchHit.Locator(pageIndex: page)
        )
    }

    @Test("empty query clears hits and does not call provider")
    func emptyQuery() async {
        var calls = 0
        let state = ReaderFindBarState(debounceInterval: .zero) { _ in
            calls += 1
            return []
        }
        await state.submit(query: "   ")
        #expect(calls == 0)
        #expect(state.hits.isEmpty)
        #expect(state.hasSearched == false)
    }

    @Test("submit stores hits, sets currentIndex to 0, marks hasSearched")
    func submitStoresHits() async {
        let expected = [makeHit("a"), makeHit("b")]
        let state = ReaderFindBarState(debounceInterval: .zero) { query in
            #expect(query == "alpha")
            return expected
        }
        await state.submit(query: "alpha")
        #expect(state.hits == expected)
        #expect(state.currentIndex == 0)
        #expect(state.hasSearched)
        #expect(state.isSearching == false)
    }

    @Test("no results marks hasNoResults after a non-empty query")
    func noResultsState() async {
        let state = ReaderFindBarState(debounceInterval: .zero) { _ in [] }
        #expect(state.hasNoResults == false)
        await state.submit(query: "nothing")
        #expect(state.hasSearched)
        #expect(state.hasNoResults)
    }

    @Test("next and previous wrap around")
    func navigationWraps() async {
        let state = ReaderFindBarState(debounceInterval: .zero) { _ in
            [self.makeHit("a"), self.makeHit("b"), self.makeHit("c")]
        }
        await state.submit(query: "q")
        #expect(state.currentIndex == 0)
        state.next()
        #expect(state.currentIndex == 1)
        state.next()
        #expect(state.currentIndex == 2)
        state.next()
        #expect(state.currentIndex == 0)
        state.previous()
        #expect(state.currentIndex == 2)
    }

    @Test("clear resets query, hits, currentIndex, and hasSearched")
    func clearResets() async {
        let state = ReaderFindBarState(debounceInterval: .zero) { _ in
            [self.makeHit("a"), self.makeHit("b")]
        }
        await state.submit(query: "q")
        state.next()
        state.clear()
        #expect(state.query.isEmpty)
        #expect(state.hits.isEmpty)
        #expect(state.currentIndex == 0)
        #expect(state.hasSearched == false)
        #expect(state.hasNoResults == false)
    }

    @Test("debounced scheduleSubmit only runs the latest query")
    func debounceCoalescesCalls() async {
        var recorded: [String] = []
        let state = ReaderFindBarState(debounceInterval: .milliseconds(40)) { query in
            recorded.append(query)
            return [ReaderSearchHit(snippet: query, locator: .init())]
        }
        state.scheduleSubmit(query: "a")
        state.scheduleSubmit(query: "al")
        state.scheduleSubmit(query: "alpha")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(recorded == ["alpha"])
        #expect(state.hits.first?.snippet == "alpha")
    }

    @Test("currentHit returns the hit at currentIndex")
    func currentHitAccessor() async {
        let state = ReaderFindBarState(debounceInterval: .zero) { _ in
            [self.makeHit("first"), self.makeHit("second")]
        }
        await state.submit(query: "q")
        #expect(state.currentHit?.snippet == "first")
        state.next()
        #expect(state.currentHit?.snippet == "second")
    }
}
