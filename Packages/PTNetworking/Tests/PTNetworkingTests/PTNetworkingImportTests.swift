import Testing
@testable import PTNetworking

@Suite("PTNetworking Module")
struct PTNetworkingImportTests {
    @Test("Module imports successfully")
    func moduleImports() {
        // If this compiles, the module and its PTCore re-export work
        #expect(true)
    }
}
