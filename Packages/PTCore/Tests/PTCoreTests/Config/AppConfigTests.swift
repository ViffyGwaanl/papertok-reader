import Foundation
import Testing
@testable import PTCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test("App Group suite name is correct")
    func appGroupSuiteName() {
        #expect(AppConfig.suiteName == "group.ai.papertok.paperreader")
    }

    @Test("Default values are set")
    func defaultValues() {
        #expect(AppConfig.Defaults.defaultFontSize == 18.0)
        #expect(AppConfig.Defaults.defaultPageTurnMode == "swipe")
    }
}

@Suite("KeychainService")
struct KeychainServiceTests {
    @Test("Save and load from keychain")
    func saveAndLoad() throws {
        let testKey = "test_api_key_\(UUID().uuidString)"
        try KeychainService.save(key: testKey, value: "sk-test-123")
        let loaded = try KeychainService.load(key: testKey)
        #expect(loaded == "sk-test-123")
        try KeychainService.delete(key: testKey)
        let deleted = try KeychainService.load(key: testKey)
        #expect(deleted == nil)
    }
}
