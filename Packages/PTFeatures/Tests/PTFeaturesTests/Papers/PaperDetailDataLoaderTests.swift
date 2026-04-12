import Foundation
import Testing
@testable import PTFeatures
@testable import PTNetworking

@Suite("PaperDetailDataLoader")
struct PaperDetailDataLoaderTests {
    @Test("loads paper detail using the selected language")
    func loadUsesSelectedLanguage() async throws {
        let api = RecordingPaperDetailAPI()
        let loader = PaperDetailDataLoader(api: api)

        let detail = try #require(await loader.load(paperId: 42, language: "en"))

        #expect(detail.id == 42)
        #expect(detail.title == "Test Detail")
        #expect(await api.requestedLanguagesSnapshot() == ["en"])
    }
}

private actor RecordingPaperDetailAPI: PaperTokAPIProtocol {
    private var requestedLanguages: [String] = []

    func fetchRandomPapers(limit: Int, language: String, day: String?) async throws -> [PaperTokCard] {
        []
    }

    func fetchPaperDetail(id: Int, language: String) async throws -> PaperTokDetail {
        requestedLanguages.append(language)
        let json = """
        {
          "id": \(id),
          "title": "Test Detail",
          "images": [],
          "generatedImages": []
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PaperTokDetail.self, from: json)
    }

    func requestedLanguagesSnapshot() -> [String] {
        requestedLanguages
    }
}
