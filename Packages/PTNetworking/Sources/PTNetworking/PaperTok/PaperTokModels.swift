import Foundation

// MARK: - PaperTokCard

/// A paper card from the PaperTok feed API (`/api/papers/random`).
public struct PaperTokCard: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let displayTitle: String?
    public let extract: String
    public let day: String?
    public let thumbnail: Thumbnail?
    public let thumbnails: [String]
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case id = "pageid"
        case title
        case displayTitle = "displaytitle"
        case extract
        case day
        case thumbnail
        case thumbnails
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        extract = try container.decodeIfPresent(String.self, forKey: .extract) ?? ""
        day = try container.decodeIfPresent(String.self, forKey: .day)
        thumbnail = try container.decodeIfPresent(Thumbnail.self, forKey: .thumbnail)
        thumbnails = try container.decodeIfPresent([String].self, forKey: .thumbnails) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public var bestTitle: String {
        if let dt = displayTitle, !dt.trimmingCharacters(in: .whitespaces).isEmpty {
            return dt
        }
        return title
    }

    public var thumbnailURL: String? {
        thumbnail?.source
    }

    public struct Thumbnail: Codable, Sendable, Equatable {
        public let source: String?
        public let width: Int?
        public let height: Int?
    }
}

// MARK: - PaperTokDetail

/// Full detail of a paper from the PaperTok detail API (`/api/papers/:id`).
public struct PaperTokDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let displayTitle: String?
    public let externalId: String?
    public let url: String?
    public let oneLiner: String?
    public let contentExplain: String?
    public let pdfUrl: String?
    public let pdfLocalUrl: String?
    public let epubUrl: String?
    public let epubUrlEn: String?
    public let epubUrlZh: String?
    public let epubUrlBilingual: String?
    public let images: [String]
    public let generatedImages: [PaperTokGeneratedImage]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        oneLiner = try container.decodeIfPresent(String.self, forKey: .oneLiner)
        contentExplain = try container.decodeIfPresent(String.self, forKey: .contentExplain)
        pdfUrl = try container.decodeIfPresent(String.self, forKey: .pdfUrl)
        pdfLocalUrl = try container.decodeIfPresent(String.self, forKey: .pdfLocalUrl)
        epubUrl = try container.decodeIfPresent(String.self, forKey: .epubUrl)
        epubUrlEn = try container.decodeIfPresent(String.self, forKey: .epubUrlEn)
        epubUrlZh = try container.decodeIfPresent(String.self, forKey: .epubUrlZh)
        epubUrlBilingual = try container.decodeIfPresent(String.self, forKey: .epubUrlBilingual)
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
        generatedImages = try container.decodeIfPresent([PaperTokGeneratedImage].self, forKey: .generatedImages) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, displayTitle, externalId, url, oneLiner, contentExplain
        case pdfUrl, pdfLocalUrl, epubUrl, epubUrlEn, epubUrlZh, epubUrlBilingual
        case images, generatedImages
    }

    public var bestEpubUrl: String? {
        [epubUrl, epubUrlZh, epubUrlEn, epubUrlBilingual]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var carouselImages: [String] {
        let gen = generatedImages.map(\.url).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return gen.isEmpty ? images : gen
    }
}

// MARK: - PaperTokGeneratedImage

public struct PaperTokGeneratedImage: Codable, Sendable, Equatable {
    public let url: String
    public let provider: String?
    public let lang: String?
}
