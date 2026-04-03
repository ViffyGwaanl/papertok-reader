import Testing
@testable import PTUI

@Suite("PTUI Module")
struct PTUIImportTests {
    @Test("Module imports successfully")
    func moduleImports() { #expect(true) }
}
