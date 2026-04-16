import Testing
import SwiftUI
@testable import PTUI

@Suite("PTDialogShell")
struct PTDialogShellTests {
    @Test("Renders title, cancel, and confirm buttons")
    func rendersAllButtons() {
        let shell = PTDialogShell(
            title: "Delete Item",
            onCancel: {},
            onConfirm: {}
        ) {
            Text("Are you sure?")
        }
        let hooks = shell.testHooks
        #expect(hooks.hasConfirm == true)
    }

    @Test("Hides confirm when nil")
    func hidesConfirmWhenNil() {
        let shell = PTDialogShell(
            title: "Info",
            onCancel: {}
        ) {
            Text("Details here")
        }
        let hooks = shell.testHooks
        #expect(hooks.hasConfirm == false)
    }
}
