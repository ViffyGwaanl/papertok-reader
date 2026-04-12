import Foundation
import Observation
import PTReader

public struct ReaderImageAnalysisRequest: Sendable, Equatable {
    public let image: ReaderImageAsset
    public let prompt: String

    public init(image: ReaderImageAsset, prompt: String) {
        self.image = image
        self.prompt = prompt
    }
}

@MainActor
@Observable
public final class ReaderImageExperienceController {
    public private(set) var presentedImage: ReaderImageAsset?

    public init() {}

    public func present(_ image: ReaderImageAsset) {
        presentedImage = image
    }

    public func dismiss() {
        presentedImage = nil
    }

    public func prepareAnalysis(bookTitle: String, chapterTitle: String?) -> ReaderImageAnalysisRequest? {
        guard let image = presentedImage else {
            return nil
        }
        presentedImage = nil
        return ReaderImageAnalysisRequest(
            image: image,
            prompt: ReaderImageAnalysisPrompt.build(
                for: image,
                bookTitle: bookTitle,
                chapterTitle: chapterTitle
            )
        )
    }
}
