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

    @Test("app targets provide Chinese Info.plist localizations for display name and permissions")
    func appTargetsProvideChineseInfoPlistLocalizations() throws {
        let appHans = try localizedStrings(at: "App/zh-Hans.lproj/InfoPlist.strings")
        let appHant = try localizedStrings(at: "App/zh-Hant.lproj/InfoPlist.strings")
        let macHans = try localizedStrings(at: "App/Platform/macOS/zh-Hans.lproj/InfoPlist.strings")
        let macHant = try localizedStrings(at: "App/Platform/macOS/zh-Hant.lproj/InfoPlist.strings")

        for strings in [appHans, appHant, macHans, macHant] {
            #expect(strings["CFBundleDisplayName"]?.isEmpty == false)
            #expect(strings["CFBundleDisplayName"] != "PaperTok Reader")
            #expect(strings["NSCalendarsUsageDescription"]?.isEmpty == false)
            #expect(strings["NSCalendarsFullAccessUsageDescription"]?.isEmpty == false)
            #expect(strings["NSRemindersUsageDescription"]?.isEmpty == false)
            #expect(strings["NSRemindersFullAccessUsageDescription"]?.isEmpty == false)
        }
    }

    @Test("share extension provides Chinese Info.plist display-name localizations")
    func shareExtensionProvidesChineseInfoPlistLocalizations() throws {
        let hans = try localizedStrings(at: "App/Extensions/ShareExtension/zh-Hans.lproj/InfoPlist.strings")
        let hant = try localizedStrings(at: "App/Extensions/ShareExtension/zh-Hant.lproj/InfoPlist.strings")

        for strings in [hans, hant] {
            #expect(strings["CFBundleDisplayName"]?.isEmpty == false)
            #expect(strings["CFBundleDisplayName"] != "PaperTok Reader")
        }
    }

    private func localizedStrings(at relativePath: String) throws -> [String: String] {
        let fileURL = repoRoot().appendingPathComponent(relativePath)
        let dictionary = try #require(NSDictionary(contentsOf: fileURL) as? [String: String])
        return dictionary
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
