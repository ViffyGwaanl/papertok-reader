import Testing
import Foundation
@testable import PTNetworking

@Suite("PaperTokModels")
struct PaperTokModelsTests {
    @Test("Decodes PaperTokCard from API JSON")
    func decodesCard() throws {
        let json = """
        {
          "pageid": 12345,
          "title": "Attention Is All You Need",
          "displaytitle": "Attention Is All You Need",
          "extract": "A groundbreaking paper on transformer architecture",
          "day": "2026-04-01",
          "thumbnail": {"source": "https://example.com/thumb.jpg", "width": 200, "height": 150},
          "thumbnails": ["https://example.com/img1.jpg", "https://example.com/img2.jpg"],
          "url": "https://arxiv.org/abs/1706.03762"
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.id == 12345)
        #expect(card.title == "Attention Is All You Need")
        #expect(card.displayTitle == "Attention Is All You Need")
        #expect(card.extract == "A groundbreaking paper on transformer architecture")
        #expect(card.day == "2026-04-01")
        #expect(card.thumbnailURL == "https://example.com/thumb.jpg")
        #expect(card.thumbnails == ["https://example.com/img1.jpg", "https://example.com/img2.jpg"])
        #expect(card.url == "https://arxiv.org/abs/1706.03762")
    }

    @Test("PaperTokCard bestTitle prefers displayTitle")
    func bestTitle() throws {
        let json = """
        {"pageid": 1, "title": "raw", "displaytitle": "Display Title", "extract": "x"}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.bestTitle == "Display Title")
    }

    @Test("PaperTokCard bestTitle falls back to title")
    func bestTitleFallback() throws {
        let json = """
        {"pageid": 1, "title": "Fallback", "extract": "x"}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(PaperTokCard.self, from: json)
        #expect(card.bestTitle == "Fallback")
    }

    @Test("Decodes PaperTokDetail from API JSON")
    func decodesDetail() throws {
        let json = """
        {
          "id": 42,
          "title": "BERT",
          "display_title": "BERT: Pre-training",
          "external_id": "arxiv-1810.04805",
          "url": "https://arxiv.org/abs/1810.04805",
          "one_liner": "A language model",
          "content_explain": "Detailed explanation here",
          "pdf_url": "https://arxiv.org/pdf/1810.04805.pdf",
          "epub_url": "https://papertok.ai/epub/42.epub",
          "epub_url_en": "https://papertok.ai/epub/42_en.epub",
          "epub_url_zh": "https://papertok.ai/epub/42_zh.epub",
          "epub_url_bilingual": null,
          "images": ["https://example.com/fig1.png"],
          "generated_images": [
            {"url": "https://example.com/gen1.png", "provider": "seedream", "lang": "en"}
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.id == 42)
        #expect(detail.title == "BERT")
        #expect(detail.displayTitle == "BERT: Pre-training")
        #expect(detail.pdfUrl == "https://arxiv.org/pdf/1810.04805.pdf")
        #expect(detail.images == ["https://example.com/fig1.png"])
        #expect(detail.generatedImages.count == 1)
        #expect(detail.generatedImages[0].provider == "seedream")
    }

    @Test("PaperTokDetail bestEpubUrl priority")
    func bestEpubUrl() throws {
        let json = """
        {
          "id": 1, "title": "T",
          "epub_url": "https://a.com/main.epub",
          "epub_url_zh": "https://a.com/zh.epub",
          "epub_url_en": "https://a.com/en.epub"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.bestEpubUrl == "https://a.com/main.epub")
    }

    @Test("PaperTokDetail carouselImages prefers generated")
    func carouselImages() throws {
        let json = """
        {
          "id": 1, "title": "T",
          "images": ["https://a.com/static.png"],
          "generated_images": [
            {"url": "https://a.com/gen.png", "provider": "p"}
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.carouselImages == ["https://a.com/gen.png"])
    }
}
