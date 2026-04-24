import Foundation
import Testing
@testable import PTFeatures

@Suite("ContextMenu action grouping")
struct ContextMenuActionGroupingTests {

    @Test("primary row shows the four most common actions")
    func primaryActionsAreFour() {
        let primary = ContextMenuActionGrouping.primaryActions
        #expect(primary.count == 4)
        #expect(primary == [.note, .copy, .translate, .define])
    }

    @Test("More… sheet surfaces the remaining actions")
    func moreActionsContainsRemaining() {
        let more = ContextMenuActionGrouping.moreActions
        // The 4 primary actions (note/copy/translate/define) are excluded.
        #expect(more == [.explain, .summarize, .search, .share])
        #expect(Set(more).isDisjoint(with: Set(ContextMenuActionGrouping.primaryActions)))
    }

    @Test("primary + more together cover all 8 selection actions")
    func allEightActionsAvailable() {
        let primary = ContextMenuActionGrouping.primaryActions
        let more = ContextMenuActionGrouping.moreActions
        let combined = Set(primary + more)

        // All selection actions except `.highlight` (which lives in the top
        // annotation swatch row, not the action grid).
        let expected: Set<ContextMenuAction> = [
            .note, .copy, .translate, .define,
            .explain, .summarize, .search, .share
        ]
        #expect(combined == expected)
        #expect(combined.count == 8)
    }
}
