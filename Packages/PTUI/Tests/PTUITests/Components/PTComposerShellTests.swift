import Testing
import SwiftUI
@testable import PTUI

@Suite("PTComposerShell")
struct PTComposerShellTests {
    @Test("Send button disabled when isSendDisabled is true")
    func sendButtonDisabled() {
        let shell = PTComposerShell(
            text: .constant("Hello"),
            placeholder: "Type here",
            onSend: {},
            isSendDisabled: true
        )
        #expect(shell.testHooks.isSendDisabled == true)
    }

    @Test("Send button enabled when isSendDisabled is false")
    func sendButtonEnabled() {
        let shell = PTComposerShell(
            text: .constant("Hello"),
            placeholder: "Type here",
            onSend: {},
            isSendDisabled: false
        )
        #expect(shell.testHooks.isSendDisabled == false)
    }

    @Test("Text binding is accessible")
    func textBindingWorks() {
        var text = "Draft"
        let binding = Binding(get: { text }, set: { text = $0 })
        let shell = PTComposerShell(
            text: binding,
            placeholder: "Type here",
            onSend: {}
        )
        #expect(shell.testHooks.currentText == "Draft")
    }
}
