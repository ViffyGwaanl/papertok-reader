#if canImport(UIKit)
import Foundation
import Testing
@testable import PTReader

@Suite("EPUBImageScriptBridge")
struct EPUBImageScriptBridgeTests {
    @Test("asset decodes image data and metadata from a JS message body")
    func assetDecodesFromMessageBody() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let body: [String: Any] = [
            "dataURL": "data:image/png;base64,\(pngData.base64EncodedString())",
            "alt": "Figure 1",
            "title": "Study Diagram",
            "sourceURL": "chapter-1.xhtml#figure-1"
        ]

        let asset = try #require(EPUBImageScriptBridge.asset(from: body))
        #expect(asset.data == pngData)
        #expect(asset.mimeType == "image/png")
        #expect(asset.altText == "Figure 1")
        #expect(asset.title == "Study Diagram")
        #expect(asset.sourceURL == "chapter-1.xhtml#figure-1")
        #expect(asset.filename == "reader-image.png")
    }

    @Test("asset returns nil when the message body is missing image data")
    func assetReturnsNilForInvalidBody() {
        #expect(EPUBImageScriptBridge.asset(from: ["alt": "Missing data"]) == nil)
        #expect(EPUBImageScriptBridge.asset(from: ["dataURL": "not-a-data-url"]) == nil)
    }
}
#endif
