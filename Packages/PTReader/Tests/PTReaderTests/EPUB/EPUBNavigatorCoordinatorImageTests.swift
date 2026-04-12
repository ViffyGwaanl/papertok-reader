#if canImport(UIKit)
import Foundation
import Testing
@testable import PTReader

@MainActor
@Suite("EPUBNavigatorCoordinator image handling")
struct EPUBNavigatorCoordinatorImageTests {
    @Test("handleImageMessage forwards decoded assets to the image callback")
    func handleImageMessageForwardsAsset() {
        let coordinator = EPUBNavigatorCoordinator()
        var receivedAsset: ReaderImageAsset?
        coordinator.onImageActivate = { receivedAsset = $0 }

        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        coordinator.handleImageMessage([
            "dataURL": "data:image/png;base64,\(pngData.base64EncodedString())",
            "title": "Figure 1"
        ])

        #expect(receivedAsset?.data == pngData)
        #expect(receivedAsset?.title == "Figure 1")
    }
}
#endif
