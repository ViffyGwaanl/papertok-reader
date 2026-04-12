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
          "source": "hf_daily",
          "day": "2026-02-05",
          "title": "BERT",
          "display_title": "BERT: Pre-training",
          "external_id": "arxiv-1810.04805",
          "url": "https://arxiv.org/abs/1810.04805",
          "thumbnail_url": "https://example.com/thumb.png",
          "text_variant": "default",
          "caption_variant": "default",
          "one_liner": "A language model",
          "one_liner_en": "An English one-liner",
          "content_explain_cn": "中文解读",
          "content_explain_en": "English explanation",
          "content_explain": "Detailed explanation here",
          "content_dialogue": "中文对话版",
          "content_dialogue_en": "English dialogue",
          "pdf_url": "https://arxiv.org/pdf/1810.04805.pdf",
          "raw_markdown_url": "https://example.com/raw.md",
          "epub_url": "https://papertok.ai/epub/42.epub",
          "epub_url_en": "https://papertok.ai/epub/42_en.epub",
          "epub_url_zh": "https://papertok.ai/epub/42_zh.epub",
          "epub_url_bilingual": null,
          "images": ["https://example.com/fig1.png"],
          "image_captions": {"https://example.com/fig1.png":"Figure 1"},
          "created_at": "2026-02-05T11:43:35.774462",
          "updated_at": "2026-04-02T10:07:43.407128",
          "generated_images": [
            {"url": "https://example.com/gen1.png", "provider": "seedream", "lang": "en"}
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)
        #expect(detail.id == 42)
        #expect(detail.source == "hf_daily")
        #expect(detail.day == "2026-02-05")
        #expect(detail.title == "BERT")
        #expect(detail.displayTitle == "BERT: Pre-training")
        #expect(detail.thumbnailUrl == "https://example.com/thumb.png")
        #expect(detail.textVariant == "default")
        #expect(detail.captionVariant == "default")
        #expect(detail.oneLinerEn == "An English one-liner")
        #expect(detail.contentExplainCn == "中文解读")
        #expect(detail.contentExplainEn == "English explanation")
        #expect(detail.contentDialogue == "中文对话版")
        #expect(detail.contentDialogueEn == "English dialogue")
        #expect(detail.pdfUrl == "https://arxiv.org/pdf/1810.04805.pdf")
        #expect(detail.rawMarkdownUrl == "https://example.com/raw.md")
        #expect(detail.images == ["https://example.com/fig1.png"])
        #expect(detail.imageCaptions?["https://example.com/fig1.png"] == "Figure 1")
        #expect(detail.generatedImages.count == 1)
        #expect(detail.generatedImages[0].provider == "seedream")
        #expect(detail.createdAt != nil)
        #expect(detail.updatedAt != nil)
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

    @Test("PaperTokDetail prefers language-specific explanation and dialogue")
    func preferredLocalizedContent() throws {
        let json = """
        {
          "id": 1,
          "title": "T",
          "content_explain": "Fallback explanation",
          "content_explain_cn": "中文解释",
          "content_explain_en": "English explanation",
          "content_dialogue": "默认对话",
          "content_dialogue_en": "English dialogue"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(PaperTokDetail.self, from: json)

        #expect(detail.preferredExplanation(language: "zh") == "中文解释")
        #expect(detail.preferredExplanation(language: "en") == "English explanation")
        #expect(detail.preferredDialogue(language: "zh") == "默认对话")
        #expect(detail.preferredDialogue(language: "en") == "English dialogue")
    }
}
