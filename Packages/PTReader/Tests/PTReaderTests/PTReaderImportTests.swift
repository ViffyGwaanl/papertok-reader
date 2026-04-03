import Testing
@testable import PTReader

@Suite("PTReader Module")
struct PTReaderImportTests {
    @Test("Module imports successfully")
    func moduleImports() {
        #expect(true)
    }
}
