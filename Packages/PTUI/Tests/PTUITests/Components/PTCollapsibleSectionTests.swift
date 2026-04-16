import Testing
import SwiftUI
@testable import PTUI

@Suite("PTCollapsibleSection")
struct PTCollapsibleSectionTests {
    @Test("Starts collapsed when binding is false")
    func startsCollapsed() {
        let section = PTCollapsibleSection(
            title: "Advanced",
            isExpanded: .constant(false)
        ) {
            Text("Hidden content")
        }
        #expect(section.testHooks.isExpanded == false)
    }

    @Test("Reports expanded when binding is true")
    func reportsExpanded() {
        let section = PTCollapsibleSection(
            title: "Advanced",
            isExpanded: .constant(true)
        ) {
            Text("Visible content")
        }
        #expect(section.testHooks.isExpanded == true)
    }
}
