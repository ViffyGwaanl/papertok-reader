import Testing
@testable import PTFeatures

@Suite("PTFeatures Module")
struct PTFeaturesImportTests {
    @Test("Module imports successfully")
    func moduleImports() { #expect(true) }
}
