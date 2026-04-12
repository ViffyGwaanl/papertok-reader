import Foundation
import Testing
@testable import PTFeatures
import PTReader

@MainActor
@Suite("ReaderImageExperienceController")
struct ReaderImageExperienceControllerTests {
    @Test("prepareAnalysis builds a request and dismisses the current image")
    func prepareAnalysisBuildsRequest() throws {
        let controller = ReaderImageExperienceController()
        let asset = ReaderImageAsset(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png",
            title: "Figure 2",
            altText: "Sample cell diagram"
        )

        controller.present(asset)
        let request = try #require(
            controller.prepareAnalysis(
                bookTitle: "The Swift Migration",
                chapterTitle: "Wave 2"
            )
        )

        #expect(request.image == asset)
        #expect(request.prompt.contains("The Swift Migration"))
        #expect(request.prompt.contains("Wave 2"))
        #expect(controller.presentedImage == nil)
    }

    @Test("dismiss clears the presented image")
    func dismissClearsPresentedImage() {
        let controller = ReaderImageExperienceController()
        controller.present(
            ReaderImageAsset(
                data: Data([0xFF, 0xD8, 0xFF]),
                mimeType: "image/jpeg"
            )
        )

        controller.dismiss()

        #expect(controller.presentedImage == nil)
    }
}
