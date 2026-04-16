import Foundation
import Testing
@testable import PTFeatures
@testable import PTNetworking

@Suite("Paper EPUB variant picker")
struct PaperEPUBVariantPickerTests {

    @Test("Exposes only variants whose URL is populated")
    func listsOnlyPresentVariants() throws {
        let detail = try makeDetail(
            epub: "/epub/default.epub",
            epubZh: "/epub/zh.epub",
            epubEn: nil,
            epubBilingual: nil
        )

        let variants = PaperDownloadPlan.availableEpubVariants(for: detail)
        let kinds = variants.map(\.kind)

        #expect(kinds == [.default, .chinese])
    }

    @Test("Returns empty when no EPUB variants are present")
    func emptyWhenNoEPUBs() throws {
        let detail = try makeDetail(epub: nil, epubZh: nil, epubEn: nil, epubBilingual: nil)
        let variants = PaperDownloadPlan.availableEpubVariants(for: detail)
        #expect(variants.isEmpty)
    }

    @Test("Treats whitespace-only URLs as absent")
    func whitespaceTreatedAsMissing() throws {
        let detail = try makeDetail(epub: "   ", epubZh: "/epub/zh.epub", epubEn: nil, epubBilingual: nil)
        let variants = PaperDownloadPlan.availableEpubVariants(for: detail)
        #expect(variants.map(\.kind) == [.chinese])
    }

    @Test("Download plan for Chinese variant picks the Chinese URL")
    func planForChineseVariantPicksChineseURL() throws {
        let detail = try makeDetail(
            epub: "/epub/default.epub",
            epubZh: "/epub/zh.epub",
            epubEn: "/epub/en.epub",
            epubBilingual: "/epub/bilingual.epub"
        )
        let plan = try #require(PaperDownloadPlan(detail: detail, variant: .chinese))
        #expect(plan.format == .epub)
        #expect(plan.variant == .chinese)
        #expect(plan.downloadURL.absoluteString.hasSuffix("/epub/zh.epub"))
    }

    @Test("Download plan for English variant picks the English URL")
    func planForEnglishVariantPicksEnglishURL() throws {
        let detail = try makeDetail(
            epub: nil,
            epubZh: "/epub/zh.epub",
            epubEn: "/epub/en.epub",
            epubBilingual: nil
        )
        let plan = try #require(PaperDownloadPlan(detail: detail, variant: .english))
        #expect(plan.variant == .english)
        #expect(plan.downloadURL.absoluteString.hasSuffix("/epub/en.epub"))
    }

    @Test("Download plan for Bilingual variant picks the bilingual URL")
    func planForBilingualVariantPicksBilingualURL() throws {
        let detail = try makeDetail(
            epub: nil,
            epubZh: nil,
            epubEn: nil,
            epubBilingual: "/epub/bilingual.epub"
        )
        let plan = try #require(PaperDownloadPlan(detail: detail, variant: .bilingual))
        #expect(plan.variant == .bilingual)
        #expect(plan.downloadURL.absoluteString.hasSuffix("/epub/bilingual.epub"))
    }

    @Test("Requesting a variant that is not exposed returns nil")
    func missingVariantYieldsNilPlan() throws {
        let detail = try makeDetail(
            epub: nil,
            epubZh: "/epub/zh.epub",
            epubEn: nil,
            epubBilingual: nil
        )
        #expect(PaperDownloadPlan(detail: detail, variant: .english) == nil)
        #expect(PaperDownloadPlan(detail: detail, variant: .bilingual) == nil)
    }

    @Test("Variant titleKey is stable and distinct per case")
    func titleKeyStable() {
        #expect(PaperEpubVariant.default.titleKey == "papers.detail.epub_variant.default")
        #expect(PaperEpubVariant.chinese.titleKey == "papers.detail.epub_variant.chinese")
        #expect(PaperEpubVariant.english.titleKey == "papers.detail.epub_variant.english")
        #expect(PaperEpubVariant.bilingual.titleKey == "papers.detail.epub_variant.bilingual")
    }

    // MARK: - Helpers

    private func makeDetail(
        epub: String?,
        epubZh: String?,
        epubEn: String?,
        epubBilingual: String?
    ) throws -> PaperTokDetail {
        var fields: [String] = []
        if let epub { fields.append("\"epubUrl\": \"\(epub)\"") }
        if let epubZh { fields.append("\"epubUrlZh\": \"\(epubZh)\"") }
        if let epubEn { fields.append("\"epubUrlEn\": \"\(epubEn)\"") }
        if let epubBilingual { fields.append("\"epubUrlBilingual\": \"\(epubBilingual)\"") }
        let body = fields.map { "          \($0)," }.joined(separator: "\n")
        let json = """
        {
          "id": 42,
          "title": "A Paper",
        \(body)
          "images": [],
          "generatedImages": []
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PaperTokDetail.self, from: json)
    }
}
