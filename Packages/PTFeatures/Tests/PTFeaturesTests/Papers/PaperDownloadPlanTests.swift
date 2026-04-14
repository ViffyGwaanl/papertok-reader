import Foundation
import Testing
@testable import PTFeatures
@testable import PTNetworking

@Suite("PaperDownloadPlan")
struct PaperDownloadPlanTests {
    @Test("Prefers EPUB when PaperTok detail exposes both EPUB and PDF")
    func prefersEPUB() throws {
        let detail = try makeDetail(
            pdfURL: "https://papertok.ai/pdf/paper.pdf",
            epubURL: "/epub/paper.epub"
        )

        let plan = try #require(PaperDownloadPlan(detail: detail))

        #expect(plan.format == .epub)
        #expect(plan.buttonTitle == AppLocalization.string("papers.import_epub"))
        #expect(plan.downloadURL.absoluteString == "https://papertok.ai/epub/paper.epub")
        #expect(plan.suggestedFilename.hasSuffix(".epub"))
    }

    @Test("Falls back to PDF when no EPUB is available")
    func fallsBackToPDF() throws {
        let detail = try makeDetail(
            pdfURL: "https://papertok.ai/pdf/paper.pdf",
            epubURL: nil
        )

        let plan = try #require(PaperDownloadPlan(detail: detail))

        #expect(plan.format == .pdf)
        #expect(plan.buttonTitle == AppLocalization.string("papers.import_pdf"))
        #expect(plan.downloadURL.absoluteString == "https://papertok.ai/pdf/paper.pdf")
        #expect(plan.suggestedFilename.hasSuffix(".pdf"))
    }

    private func makeDetail(pdfURL: String?, epubURL: String?) throws -> PaperTokDetail {
        let pdfField = pdfURL.map { "\"pdfUrl\": \"\($0)\"," } ?? ""
        let epubField = epubURL.map { "\"epubUrl\": \"\($0)\"," } ?? ""
        let json = """
        {
          "id": 7,
          "title": "Transformers",
          \(pdfField)
          \(epubField)
          "images": [],
          "generatedImages": []
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PaperTokDetail.self, from: json)
    }
}
