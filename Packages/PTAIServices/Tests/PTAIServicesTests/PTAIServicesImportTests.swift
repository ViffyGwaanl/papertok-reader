import Testing
@testable import PTAIServices

@Suite("PTAIServices Module")
struct PTAIServicesImportTests {
    @Test("Module imports successfully")
    func moduleImports() { #expect(true) }
}
