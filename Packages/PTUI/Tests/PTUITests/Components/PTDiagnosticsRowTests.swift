import Testing
import SwiftUI
@testable import PTUI

@Suite("PTDiagnosticsRow")
struct PTDiagnosticsRowTests {
    @Test("Renders label and value")
    func rendersLabelAndValue() {
        let row = PTDiagnosticsRow(label: "Version", value: "1.2.3")
        #expect(row.testHooks.value == "1.2.3")
    }

    @Test("Copy button present when copyable is true")
    func copyButtonPresent() {
        let row = PTDiagnosticsRow(label: "Build", value: "42", copyable: true)
        #expect(row.testHooks.copyable == true)
    }

    @Test("Copy button absent when copyable is false")
    func copyButtonAbsent() {
        let row = PTDiagnosticsRow(label: "Build", value: "42", copyable: false)
        #expect(row.testHooks.copyable == false)
    }
}
