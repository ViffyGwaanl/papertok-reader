import Foundation
import Testing

@Suite("ShareExtension Info.plist")
struct ShareExtensionInfoPlistTests {
    @Test("share extension advertises text, url, image, and file support")
    func activationRulesCoverRequiredContentTypes() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("ShareExtension", isDirectory: true)
            .appendingPathComponent("Info.plist")

        let plist = try #require(NSDictionary(contentsOf: plistURL) as? [String: Any])
        let extensionDict = try #require(plist["NSExtension"] as? [String: Any])
        let attributes = try #require(extensionDict["NSExtensionAttributes"] as? [String: Any])
        let activationRule = try #require(attributes["NSExtensionActivationRule"] as? [String: Any])

        #expect(activationRule["NSExtensionActivationSupportsText"] as? Bool == true)
        #expect((activationRule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? NSNumber)?.intValue == 10)
        #expect((activationRule["NSExtensionActivationSupportsImageWithMaxCount"] as? NSNumber)?.intValue == 10)
        #expect((activationRule["NSExtensionActivationSupportsFileWithMaxCount"] as? NSNumber)?.intValue == 10)
    }
}
